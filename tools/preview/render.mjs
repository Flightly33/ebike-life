// Offline renders of a part list (from tools/lune/preview_export.luau) with three.js in headless
// Chromium, so geometry can be checked without Studio.
//
//   node tools/preview/render.mjs <parts.json> <views.json> <outdir>
//
// views.json: [{ "name": "spawn", "pos": [x, y, z], "look": [x, y, z], "fov": 60,
//                "width": 1280, "height": 720, "shadows": true, "ortho": 0 }]
// ortho > 0 renders a top-down orthographic map that many studs across.
import { chromium } from "playwright";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const [partsPath, viewsPath, outDir] = process.argv.slice(2);
if (!partsPath || !viewsPath || !outDir) {
	console.error("usage: node render.mjs <parts.json> <views.json> <outdir>");
	process.exit(1);
}
const parts = JSON.parse(fs.readFileSync(partsPath, "utf8"));
const views = JSON.parse(fs.readFileSync(viewsPath, "utf8"));
fs.mkdirSync(outDir, { recursive: true });

const browser = await chromium.launch({
	args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"],
});
const page = await browser.newPage();
page.on("console", (msg) => {
	if (msg.type() === "error") console.error("[page]", msg.text());
});
await page.setContent("<html><body style='margin:0;background:#000'></body></html>");
await page.addScriptTag({ path: path.join(here, "node_modules/three/build/three.min.js") });

await page.evaluate((parts) => {
	const T = window.THREE;
	const scene = new T.Scene();
	scene.background = new T.Color(0x9fc8ec);
	scene.fog = new T.Fog(0xb8d4ee, 1200, 5200);
	window.__scene = scene;

	const hemi = new T.HemisphereLight(0xdfefff, 0x5f6b4f, 1.15);
	scene.add(hemi);
	const sun = new T.DirectionalLight(0xfff4e0, 2.1);
	sun.position.set(-300, 600, 250);
	sun.castShadow = true;
	sun.shadow.mapSize.set(4096, 4096);
	sun.shadow.bias = -0.0005;
	scene.add(sun);
	scene.add(sun.target);
	window.__sun = sun;

	const box = new T.BoxGeometry(1, 1, 1);
	const cyl = new T.CylinderGeometry(0.5, 0.5, 1, 20);
	cyl.rotateZ(-Math.PI / 2); // Roblox cylinders run along X
	const sphere = new T.SphereGeometry(0.5, 18, 12);
	const geos = { Block: box, Cylinder: cyl, Ball: sphere };

	const groups = {};
	const m4 = new T.Matrix4();
	const scl = new T.Matrix4();
	const color = new T.Color();
	const singles = [];
	for (const p of parts) {
		const [x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22] = p.cf;
		m4.set(r00, r01, r02, x, r10, r11, r12, y, r20, r21, r22, z, 0, 0, 0, 1);
		scl.makeScale(p.size[0], p.size[1], p.size[2]);
		const matrix = m4.clone().multiply(scl);
		const shape = geos[p.shape] ? p.shape : "Block";
		const special = p.material === "Neon" || p.transparency > 0.05 || p.material === "Glass" || p.material === "Foil" || p.material === "Metal";
		if (special) {
			singles.push({ p, matrix, shape });
			continue;
		}
		const key = shape;
		(groups[key] ||= []).push({ p, matrix });
	}
	for (const [shape, list] of Object.entries(groups)) {
		const mat = new T.MeshStandardMaterial({ roughness: 0.85, metalness: 0.0 });
		const mesh = new T.InstancedMesh(geos[shape], mat, list.length);
		list.forEach((e, i) => {
			mesh.setMatrixAt(i, e.matrix);
			color.setRGB(e.p.color[0], e.p.color[1], e.p.color[2], T.SRGBColorSpace);
			mesh.setColorAt(i, color);
		});
		mesh.castShadow = true;
		mesh.receiveShadow = true;
		scene.add(mesh);
	}
	for (const { p, matrix, shape } of singles) {
		const c = new T.Color().setRGB(p.color[0], p.color[1], p.color[2], T.SRGBColorSpace);
		let mat;
		if (p.material === "Neon") {
			mat = new T.MeshStandardMaterial({ color: c, emissive: c, emissiveIntensity: 1.4 });
		} else if (p.material === "Glass") {
			mat = new T.MeshStandardMaterial({ color: c, roughness: 0.1, metalness: 0.5, transparent: p.transparency > 0.05, opacity: 1 - p.transparency * 0.8 });
		} else if (p.material === "Metal" || p.material === "Foil") {
			mat = new T.MeshStandardMaterial({ color: c, roughness: 0.35, metalness: 0.7 });
		} else {
			mat = new T.MeshStandardMaterial({ color: c, roughness: 0.8, transparent: true, opacity: 1 - p.transparency });
		}
		const mesh = new T.Mesh(geos[shape], mat);
		mesh.matrixAutoUpdate = false;
		mesh.matrix.copy(matrix);
		mesh.castShadow = p.transparency < 0.5;
		mesh.receiveShadow = true;
		scene.add(mesh);
	}

	const renderer = new T.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
	renderer.shadowMap.enabled = true;
	renderer.shadowMap.type = T.PCFSoftShadowMap;
	renderer.outputColorSpace = T.SRGBColorSpace;
	renderer.toneMapping = T.ACESFilmicToneMapping;
	renderer.toneMappingExposure = 1.0;
	document.body.appendChild(renderer.domElement);
	window.__renderer = renderer;
}, parts);

for (const view of views) {
	const dataUrl = await page.evaluate((view) => {
		const T = window.THREE;
		const renderer = window.__renderer;
		const scene = window.__scene;
		const w = view.width || 1280;
		const h = view.height || 720;
		renderer.setSize(w, h);
		renderer.shadowMap.enabled = view.shadows !== false;
		let camera;
		const look = new T.Vector3(...view.look);
		if (view.ortho) {
			const half = view.ortho / 2;
			const aspect = w / h;
			camera = new T.OrthographicCamera(-half * aspect, half * aspect, half, -half, 1, 10000);
			camera.position.set(look.x, 3000, look.z + 0.001);
			camera.up.set(0, 0, -1);
			camera.lookAt(look);
			scene.fog = null;
		} else {
			camera = new T.PerspectiveCamera(view.fov || 60, w / h, 0.1, 9000);
			camera.position.set(...view.pos);
			camera.lookAt(look);
		}
		// Fit the sun's shadow box around what the camera looks at
		const sun = window.__sun;
		const span = view.shadowSpan || 400;
		sun.target.position.copy(look);
		sun.position.copy(look).add(new T.Vector3(-0.45, 1, 0.35).multiplyScalar(span * 1.5));
		const sc = sun.shadow.camera;
		sc.left = -span;
		sc.right = span;
		sc.top = span;
		sc.bottom = -span;
		sc.near = 1;
		sc.far = span * 4;
		sc.updateProjectionMatrix();
		renderer.render(scene, camera);
		return renderer.domElement.toDataURL("image/png");
	}, view);
	const file = path.join(outDir, `${view.name}.png`);
	fs.writeFileSync(file, Buffer.from(dataUrl.split(",")[1], "base64"));
	console.log("wrote", file);
}
await browser.close();
