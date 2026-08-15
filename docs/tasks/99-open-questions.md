# 未决问题

文档和对照代码时留下的拍板项。没定之前，对应任务按「建议方案」做，但不要当成不可改的需求。

| ID | 问题 | 建议 | 影响 |
|---|---|---|---|
| Q1 | 批处理做独立面板，还是各功能一个按钮？ | 各功能按钮 + 共用 BatchRunner，不新增 Tab | [07](./07-batch.md) |
| Q2 | 标题栏「深蓝」的精确色值（是否仍用 jamovi `#3E6DA9`） | 向 X-Lab 要 token | [01](./01-branding.md) |
| Q3 | 导出数据是否包含过滤后的行、计算列、隐藏列 | 导出「当前表所见」：含计算列，尊重过滤 | [03](./03-file-io.md) |
| Q4 | 是否保留模块侧载 / jamovi library | 生产关闭；开发者模式打开 | [04](./04-modules.md) |
| Q5 | 通用 Rj 是否对客户开放 | 关闭。LASSO 等做成正式模块 | [04](./04-modules.md)、[09](./09-survival-roc.md) |
| Q6 | Alluvial 用 ClinicoPath 还是 Rj | ClinicoPath，挂到 EDA | [06](./06-eda-plots.md) |
| Q7 | 和弦图库（circlize 等）与交互程度 | 静态 ggplot/circlize + 选项窗即可 | [06](./06-eda-plots.md) |
| Q8 | snowCluster 独立 MDS/PCA 可视化是否舍弃 | P2 舍弃，热图自带树 | [10](./10-clustering.md) |
| Q9 | LASSO 默认 `lambda.min` 还是 `lambda.1se` | 默认 `lambda.1se`，可切换 | [09](./09-survival-roc.md) |
| Q10 | Box Plot p 值：自动选检验还是用户指定 | 与组间向导同一规则，可覆盖 | [06](./06-eda-plots.md)、[08](./08-stats-workflows.md) |
| Q11 | FDR / 多重校正 | 按文档暂缓 | P3+ |
| Q12 | 内部 bootstrap、外部验证 | 文档未跑通；P2 做公式导出，验证放 P3 | [09](./09-survival-roc.md) |
| Q13 | AI 用哪家模型、数据是否允许出域 | 默认私有化；无配置则禁用 | [11](./11-ai-archive.md) |
| Q14 | 安装包（NSIS/MSIX）是否在本仓库建设 | 当前在仓库外；需对接产品名与图标 | [01](./01-branding.md) |
| Q15 | 欢迎页：本地静态还是自建 URL | 本地静态，避免依赖 jamovi.org | [01](./01-branding.md) |
| Q16 | 比率计算独立面板 vs 数据转换里一项 | 数据面板「转换」分组一项 | [08](./08-stats-workflows.md) |
| Q17 | 登录页：当前 Electron 桌面版无登录 | 若 X-Lab 要账号，另开需求；P0 不做 | [01](./01-branding.md) |
| Q18 | ClinicoPath 等外部模块的 fork / 许可 | 法务确认后再改热图和生存 UI | [04](./04-modules.md) |
| Q19 | 中英文：产品是否只中文 | P0 中文 UI；i18n 框架保留 | [02](./02-shell-ux.md) |
| Q20 | `.omv` 格式是否改扩展名 | **不改**，避免失兼容；资源管理器显示名可写 X-Stat | [03](./03-file-io.md) |

## 文档与代码的明显差异（实施时注意）

1. 需求写「登录页」——桌面 jamovi 没有登录，只有 splash + 欢迎 iframe。  
2. 需求写预装大量插件——仓库 Docker 只装 `jmv` + `plots`。  
3. Pareto 图在需求里是 EDA 按钮，代码里不存在。  
4. 「Z-score 后无法过滤」是真实产品缺陷，清洗工具必须绕开或修过滤。  
5. 多因素 Cox 缺 B 值——风险评分公式的阻塞点，生存模块必改。  
6. 项目管理全部在 X-Lab，不要在 Ribbon 再做看板。
