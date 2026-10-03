/*
 * @Description: 从软件 SVG 标志生成 Windows 多尺寸应用图标和高清预览。
 * @Author: LILYGO_L
 * @Date: 2026-10-03 21:36:06
 * @LastEditTime: 2026-10-03 22:48:50
 * @License: GPL 3.0
 */

// 运行需要 Node.js 和 sharp；仅用于生成资源，不参与应用运行。
const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('sharp');

async function main() {
  const root = path.resolve(__dirname, '..');
  const branding = path.join(root, 'assets/images/branding');
  const source = await fs.readFile(path.join(branding, 'lilygobox_logo.svg'), 'utf8');
  const body = source.match(/<svg\b[^>]*>([\s\S]*)<\/svg>/)?.[1];
  if (!body) throw new Error('Invalid LilygoBox SVG source');

  // 浅色底保证黑色标志在不同桌面和任务栏背景下保持清晰。
  const artwork = Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">` +
    `<rect x="4" y="4" width="248" height="248" rx="52" fill="#f6f6f8"/>` +
    `<g transform="translate(7.68 7.68) scale(.94)">${body}</g></svg>`,
  );
  const master = await sharp(artwork, { density: 576 }).png().toBuffer();
  await sharp(master).resize(1024, 1024).png().toFile(
    path.join(branding, 'lilygobox_app_icon.png'),
  );

  // 每个尺寸由高清母图独立缩小，避免系统放大小图产生锯齿。
  const sizes = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256];
  const images = await Promise.all(sizes.map((size) =>
    sharp(master).resize(size, size).png().toBuffer(),
  ));
  const directory = Buffer.alloc(6 + sizes.length * 16);
  directory.writeUInt16LE(1, 2);
  directory.writeUInt16LE(sizes.length, 4);
  let offset = directory.length;
  images.forEach((image, index) => {
    const entry = 6 + index * 16;
    directory[entry] = directory[entry + 1] = sizes[index] % 256;
    directory.writeUInt16LE(1, entry + 4);
    directory.writeUInt16LE(32, entry + 6);
    directory.writeUInt32LE(image.length, entry + 8);
    directory.writeUInt32LE(offset, entry + 12);
    offset += image.length;
  });
  await fs.writeFile(
    path.join(root, 'windows/runner/resources/app_icon.ico'),
    Buffer.concat([directory, ...images]),
  );
  console.log(`Generated Windows icon sizes: ${sizes.join(', ')}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
