# P0 · 模块预装与分析面板裁剪

## 目标

- 预装病理分析常用插件，分析面板一行排列、只显示指定模块
- 绘图/EDA 只显示指定图
- jReshape 预装，入口从分析面板挪到数据面板
- 关闭或隐藏用户乱装模块的入口（产品确认：是否保留侧载）

## 现状

本仓库 Docker 只编译：

- `jmv` → 分析 Tab（`category: analyses`）
- `plots`（scatr）→ 绘图 Tab（`category: plots`）

模块列表来自 `JAMOVI_MODULES_PATH` + 用户目录。分析菜单由 `client/main/ribbon/analysetab.ts` 按模块 `visible` 过滤。用户可通过 Store 显示/隐藏/安装（`client/main/store.ts`，源 `https://library.jamovi.org`）。

Rj 被 `JAMOVI_ALLOW_ARBITRARY_CODE` 关掉（`docker-compose.yaml` 现为 `false`）。生存 LASSO 流程需要打开它，或改成受控模块、不再暴露任意 R 控制台。

## 建议白名单（第一期）

按文档出现的功能收敛。未列入的 jmv 子分析（如 PCA、可靠性）默认隐藏。

### 分析面板

| 模块 | 用途 | 来源 |
|---|---|---|
| jmv · Exploration / Descriptives | 数值描述、缺失、正态检验 | 本仓库 submodule |
| jmv · T-Tests | 独立 / 配对 / Welch | 本仓库 |
| jmv · ANOVA | ANOVA / Welch / ANCOVA / 重复测量 | 本仓库 |
| jmv · Frequencies | 卡方 / Fisher | 本仓库 |
| jmv · Regression | 线性 / Logistic | 本仓库 |
| ClinicoPath / jsurvival | KM、Cox、ROC、生存流程 | 外部 `.jmo` |
| snowCluster | 层次聚类 / K-means | 外部 `.jmo` |
| 相关矩阵（jmv 或 jjstatsplot） | Pearson / Spearman | 按许可选择 |

### 数据面板（从分析挪走）

| 模块 | 用途 |
|---|---|
| jReshape | 长宽转换、合并（应急，主流程仍用 Excel） |

### EDA 面板

见 [06-eda-plots.md](./06-eda-plots.md)。

### 明确延后

- jamovi library 在线商店（可改为仅管理员/开发者模式）
- FDR 专用模块
- snowCluster 的 MDS / PCA 独立可视化（文档标了「舍弃？」）

## 子任务

- [ ] **T-04-01** 列出最终白名单 YAML（模块名 + analysis name），放 `docs/tasks/assets/` 或 `platform/xstat-modules.yaml`
- [ ] **T-04-02** Docker / 安装包把白名单 `.jmo` 拷进系统模块目录（改 `docker/jamovi-Dockerfile`）
- [ ] **T-04-03** 启动时按白名单 `setModuleVisibility`；非白名单不出现在分析/EDA
- [ ] **T-04-04** 分析 Tab 一行排列常用按钮，去掉「Modules / jamovi library」主入口（开发者模式可保留）
- [ ] **T-04-05** jReshape 分析改到数据 Tab 按钮（`datatab.ts` 发 `analysisSelected`，参考现有 Weights）
- [ ] **T-04-06** 生存相关模块需要任意 R 时：优先做成正式模块；若必须 Rj，仅对签名脚本开放，不要默认打开任意代码
- [ ] **T-04-07** 预装 ClinicoPath 测试数据入口（文档给了 catalog URL），放到数据库/示例
- [ ] **T-04-08** 模块版本锁定与兼容性检查（R 版本、jmvcore）

## 验收

- 干净安装后，分析面板只有白名单按钮
- 数据面板能打开 jReshape
- 普通用户看不到 jamovi library
- 打开文档所需的 KM / Cox / 描述 / 箱线图不需要再手动装插件

## 依赖

外部模块的许可证、二进制、以及能否 fork 改 UI（Box Plot p 值、聚类注释都可能要改模块源码）。
