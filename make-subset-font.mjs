/**
 * 生成采访端专用的中文子集字体。
 *
 * 为什么要做：
 * Flutter Web 默认从 fonts.gstatic.com 拉 Noto Sans SC 来渲染中文。
 * 校园内网通常没有外网，于是每次打开采访端都要等这些请求超时——
 * 这是「加载要等十多秒」的主要原因之一，而且超时后汉字根本不显示。
 *
 * 本应用界面只用到约 30 个汉字，把它们（外加 ASCII 与常用标点）从完整的
 * Noto Sans SC 里切出来只有几十 KB，随包分发即可彻底去掉 CDN 依赖。
 *
 * Noto Sans SC 采用 SIL Open Font License 1.1，允许再分发与子集化。
 *
 * 用法：node make-subset-font.mjs
 */
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const SRC_FONT = 'C:/Windows/Fonts/NotoSansSC-VF.ttf';
const OUT_DIR = 'assets/fonts';
const OUT = join(OUT_DIR, 'NotoSansSC-Subset.ttf');

// ---- 1. 收集界面里可能出现的字符 ----
// 扫 lib/ 下所有 .dart 的字符串字面量，抽出全部 CJK 字符。
// 再补一批状态/连接相关的常用字，避免后端推来新文案时缺字。
function walk(dir) {
	return readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
		const f = join(dir, e.name);
		return e.isDirectory() ? walk(f) : f.endsWith('.dart') ? [f] : [];
	});
}

const EXTRA =
	'正在播送即将切台已连接未连接连接中就绪准备离线无点采访名称状态切换点击屏幕' +
	'第共个项目条消息数量时间在线客户端版本号登录失败请稍后重试错误成功';

const chars = new Set();
for (const f of walk('lib')) {
	for (const ch of readFileSync(f, 'utf8')) {
		if (/[\u4e00-\u9fff\u3000-\u303f\uff00-\uffef]/.test(ch)) chars.add(ch);
	}
}
for (const ch of EXTRA) chars.add(ch);
// ASCII 可见字符 + 常用符号，保证数字、标点、状态点不会缺
for (let c = 0x20; c <= 0x7e; c++) chars.add(String.fromCharCode(c));
for (const ch of '·—…、。，！？：；（）【】《》“”‘’×÷±≈°′″') chars.add(ch);

const cjkCount = [...chars].filter((c) => /[\u4e00-\u9fff]/.test(c)).length;
console.log(`界面用到的汉字: ${cjkCount} 个`);
console.log(`含 ASCII 与标点后合计: ${chars.size} 个码位`);

if (!existsSync(SRC_FONT)) {
	console.error(`\n找不到源字体 ${SRC_FONT}`);
	console.error('请安装 Noto Sans SC，或改用本机其它可再分发的中文字体。');
	process.exit(1);
}
console.log(`源字体: ${SRC_FONT} (${(statSync(SRC_FONT).size / 1024 / 1024).toFixed(1)} MB)`);

// ---- 2. 调用 fonttools 子集化 ----
mkdirSync(OUT_DIR, { recursive: true });
const text = [...chars].join('');
writeFileSync('assets/.subset-charset.txt', text, 'utf8');

const unicodes = [...chars].map((c) => 'U+' + c.codePointAt(0).toString(16).toUpperCase().padStart(4, '0'));
console.log('\n调用 fonttools pyftsubset...');
execFileSync(
	'python',
	[
		'-m', 'fontTools.subset',
		SRC_FONT,
		`--text-file=assets/.subset-charset.txt`,
		`--unicodes=${unicodes.join(',')}`,
		'--layout-features=*',
		'--output-file=' + OUT,
		'--drop-tables+=DSIG',
		'--name-IDs=*',
		'--recalc-bounds',
		'--passthrough-tables'
	],
	{ stdio: 'inherit' }
);

const outSize = statSync(OUT).size;
console.log(`\n完成: ${OUT}  ${(outSize / 1024).toFixed(1)} KB`);
console.log(`从 ${(statSync(SRC_FONT).size / 1024 / 1024).toFixed(1)} MB 缩到 ${(outSize / 1024).toFixed(1)} KB`);
