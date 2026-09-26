/**
 * 裁剪采访端 Web 产物里的死重。
 *
 * 背景：`flutter build web` 会把 6 个渲染器变体、源映射、实验特性目录
 * 全部塞进产物（实测 39.8MB），但浏览器冷启动只会下载其中约 7.6MB。
 * 其余 30MB 纯粹是服务器磁盘和部署上传的负担。
 *
 * 「哪些不会被下载」是用 Playwright 的 resource timing 实测出来的，
 * 不是推测——注意引擎实际选的是 `canvaskit/chromium/`（5.6MB），
 * 而顶层那份 `canvaskit.wasm`（6.9MB）根本没被用到。
 *
 * 用法：node trim-web.mjs [产物目录]
 * 默认 ../backend/public/interviewer
 */
import { existsSync, readdirSync, rmSync, statSync } from 'node:fs';
import { join, relative, resolve, sep } from 'node:path';

const target = resolve(process.argv[2] || '../backend/public/interviewer');
if (!existsSync(target)) {
	console.error(`找不到产物目录: ${target}`);
	process.exit(1);
}

const sizeOf = (p) => statSync(p).size;
const mb = (n) => (n / 1024 / 1024).toFixed(2);
const walk = (dir) =>
	readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
		const f = join(dir, e.name);
		return e.isDirectory() ? walk(f) : [f];
	});

const before = walk(target).reduce((a, f) => a + sizeOf(f), 0);
console.log(`裁剪前: ${mb(before)} MB / ${walk(target).length} 个文件`);
console.log(`目标目录: ${target}\n`);

// 逐项删除，每项都注明「为什么确定它不会被下载」。
const removals = [
	{
		what: '源映射（*.symbols）',
		glob: /\.symbols$/,
		why: '只在 DevTools 调试时按需拉取，正常加载路径从不请求'
	},
	{
		what: 'canvaskit/ 顶层渲染器',
		exact: ['canvaskit/canvaskit.js', 'canvaskit/canvaskit.wasm'],
		why: '引擎在 Chrome/Edge 上选的是 chromium 变体，顶层这份实测未被请求（6.9MB）'
	},
	{
		what: 'skwasm 渲染器（2 个变体）',
		glob: /^canvaskit\/skwasm/,
		why: '仅当 loader 显式配置 renderer: "skwasm" 才加载；本项目用默认的 canvaskit'
	},
	{
		what: 'wimp 渲染器',
		glob: /^canvaskit\/wimp/,
		why: '同上，未被选中'
	},
	{
		what: 'experimental_webparagraph/',
		dir: 'canvaskit/experimental_webparagraph',
		why: '实验性排版引擎，需在 index.html 显式引入，默认不加载'
	}
];

let freed = 0;
for (const r of removals) {
	const files = [];
	if (r.exact) {
		for (const rel of r.exact) {
			const p = join(target, rel);
			if (existsSync(p)) files.push(p);
		}
	} else if (r.dir) {
		const p = join(target, r.dir);
		if (existsSync(p)) files.push(...walk(p));
	} else if (r.glob) {
		files.push(...walk(target).filter((f) => r.glob.test(relative(target, f).split(sep).join('/'))));
	}

	if (!files.length) {
		console.log(`  - ${r.what}: 无可删内容`);
		continue;
	}
	const sum = files.reduce((a, f) => a + sizeOf(f), 0);
	for (const f of files) rmSync(f, { force: true });
	// 清掉空目录
	if (r.dir) rmSync(join(target, r.dir), { recursive: true, force: true });
	freed += sum;
	console.log(`  - ${r.what}: 省下 ${mb(sum)} MB`);
	console.log(`      理由: ${r.why}`);
}

const after = walk(target).reduce((a, f) => a + sizeOf(f), 0);
console.log(`\n裁剪后: ${mb(after)} MB（省下 ${mb(freed)} MB，占原体积 ${((freed / before) * 100).toFixed(0)}%）`);

// 兜底断言：删完必须还留得住引擎真正要用的那一份
const required = ['canvaskit/chromium/canvaskit.js', 'canvaskit/chromium/canvaskit.wasm', 'main.dart.js', 'index.html'];
const missing = required.filter((f) => !existsSync(join(target, f)));
if (missing.length) {
	console.error('\n致命：裁剪过头，以下文件缺失:');
	for (const m of missing) console.error('  ' + m);
	process.exit(1);
}
console.log('必需文件齐全: ' + required.join(', '));
