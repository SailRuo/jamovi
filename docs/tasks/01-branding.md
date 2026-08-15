# P0 · 品牌替换（X-Stat）

## 目标

全界面去掉 jamovi 原版 logo、名称、标识；启动页、关于、窗口标题、桌面图标、安装包显示为 X-Stat。标题栏改为与 X-Lab 一致的深蓝色。

## 现状

| 位置 | 当前值 | 文件 |
|---|---|---|
| 窗口标题 | `jamovi` | `client/index.html`、`client/main/host.ts`（`APP_NAME`） |
| Electron 产品名 | `jamovi` | `electron/app/package.json`、`electron/app/preload.js` |
| 服务端应用名 | `jamovi` | `server/jamovi/server/appinfo.py` |
| 启动页 | `starting jamovi...` + SVG | `electron/app/splash.html` |
| 欢迎 iframe | `https://www.jamovi.org/welcome/` | `client/main/results.ts` |
| 结果区 logo | `jamoviIcon` | `client/common/icon.ts`、`client/assets/logo-*.svg` |
| 桌面图标 | `platform/app-icon.svg` | 安装包图标由外部 NSIS/MSIX 注入 `JAMOVI_ICON_PATH` |
| 品牌蓝 | `#3E6DA9` | `jamovi.css` / `ribbon.css` / `backstage.css` |
| 引用 | “The jamovi project” | `client/main/references.ts` |
| Linux 桌面项 | `Name=jamovi` | `platform/jamovi.desktop` |

没有独立 About 对话框；macOS 用系统 About role。

## 子任务

- [ ] **T-01-01** 抽出单一品牌常量（建议 `client/main/host.ts` + `server/.../appinfo.py`），避免各处硬编码 `jamovi`
- [ ] **T-01-02** 替换窗口标题、`aria-label`、标题栏文字（`client/index.html`）
- [ ] **T-01-03** 替换 Electron `productName`、preload `APP_NAME`、splash 文案与 logo
- [ ] **T-01-04** 设计并替换 `logo-v.svg`、`logo-v-naked.svg`、`logo-store.svg`、`platform/app-icon.svg`
- [ ] **T-01-05** 欢迎页改为 X-Stat 本地页或自有 URL，去掉 jamovi.org iframe
- [ ] **T-01-06** 标题栏 / Backstage header 颜色改为 X-Lab 深蓝（向设计确认色值；现网是 `#3E6DA9`）
- [ ] **T-01-07** 关于信息：产品名 X-Stat，同时保留「基于 jamovi」与许可证
- [ ] **T-01-08** `references.ts` / LaTeX 导出页眉中的产品名改为 X-Stat，保留 jamovi 引用条目
- [ ] **T-01-09** `platform/jamovi.desktop`、MIME 说明中的显示名
- [ ] **T-01-10** 安装包标识：与外部打包脚本对齐（本仓库无 NSIS 配置，需同步图标路径与产品名）
- [ ] **T-01-11** 全文检索 client/electron/server 中用户可见的 `jamovi` 字符串，列白名单（协议、路径、许可证可保留）

## 不要改的

- 协议 namespace、`.omv` 文件格式、`jamovi.proto` 字段名
- `LICENSE.md` 法律文本
- 模块内部 R 包名（`jmv`、`jmvcore`）——用户不可见即可

## 验收

- 冷启动 splash、窗口标题、结果区 logo 均为 X-Stat
- 界面无 jamovi 字样（关于页开源声明除外）
- 标题栏颜色与 X-Lab 一致
- Windows 安装后开始菜单 / 桌面图标为 X-Stat

## 依赖

需设计提供：logo SVG、图标 ICO/PNG、X-Lab 标准色值、欢迎页文案。
