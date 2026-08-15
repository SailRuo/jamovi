# P1 · 数据探索（EDA）与发表级图形

## 目标

绘图面板改名为 **数据探索 / EDA**：只做肉眼趋势，不做统计推断（推断在分析面板）。下设独立按钮，并补齐文档点名的图。组间 Box Plot 要能显示 p 值，样式达到可直接用于文章。

## 现状

| 图 | 现状 |
|---|---|
| Bar / Box / Histogram / Scatter / Line | `plots` 子模块 scatr，`category: plots`，大按钮在 `plotstab.ts` |
| Pareto | **本仓库没有**，需新分析或 ClinicoPath |
| Alluvial | ClinicoPathDescriptives，现在走分析 → 探索 |
| 和弦图 | 无 |
| Box Plot p 值 | 无，文档明确缺口 |
| 多变量批出图 | 无，见 [07-batch.md](./07-batch.md) |

图标：`client/assets/analysis-scatr-jmvbar.svg` 等。  
Tab 标题在 `client/main/ribbon/plotstab.ts`：`super('plots', 'P', _('Plots'))`。

## 推荐按钮（文档表）

| 按钮 | 目的 | 通量 |
|---|---|---|
| 数值描述 | 均值/中位数/SD/缺失率 + 直方图/箱线 | 多变量批处理 |
| Bar（分类） | 各组样本量/频数 | 逐个，可批 |
| Bar（连续+误差条） | 各组均值 | 逐个，可批 |
| Box Plot | 分布 / 异常值；组间比较发表图 | 逐个，可批 |
| Histogram | 正态/偏态 | 逐个，可批 |
| Scatter | 两连续变量关联 | 逐个 |
| Line | 随时间/有序变化 | 逐个 |
| Pareto | 关键少数分类 | 逐个 |
| Alluvial | 多分类流转 | 逐个 |
| 和弦图 | 细胞/标志物关系 | 逐个 |

连续变量必须用**原始值**，不用 Z-score。

## 子任务

### 面板

- [ ] **T-06-01** Plots Tab 显示名改为「数据探索」或「EDA」（内部 `name: 'plots'` 可不变）
- [ ] **T-06-02** 只显示上表按钮；scatr「More」和 jamovi library 入口隐藏
- [ ] **T-06-03** 数值描述：复用 jmv Descriptives，但入口放 EDA；多变量时支持导出到文件夹（[07](./07-batch.md)）

### 发表级 Box Plot

- [ ] **T-06-04** 组间 Box Plot 图上标注 p 值（两组：t 或 Mann-Whitney；≥3 组：ANOVA 或 Kruskal-Wallis，与分析面板规则一致）
- [ ] **T-06-05** 可选显著性括号、样本量 n、中位数标注
- [ ] **T-06-06** 导出 PNG/SVG/PDF，默认尺寸适合投稿（宽高、字体、线宽可设）
- [ ] **T-06-07** 配色/主题增加「论文」预设，减少二次 ggplot

实现优先改 `plots`（jmvplots）R 端，而不是只在 client 画。

### 其他图

- [ ] **T-06-08** Pareto：降序条形 + 累积百分比折线，终点 100%
- [ ] **T-06-09** Alluvial：预装后 `category` 改为 plots，或客户端把该 analysis 挂到 EDA
- [ ] **T-06-10** 和弦图：做成带窗口的正式分析（circlize 等），不要只丢一段 Rj
- [ ] **T-06-11** 各图的方法说明（何时用、用原始值、不做推断）

## 验收

- 面板名称与 8+ 个按钮符合文档
- 预后两组的 PD-L1 箱线图上有 p 值，导出后可直接贴 PPT/论文
- Alluvial 在 EDA 而不是分析深层菜单
- 和弦图有选项窗口，不是空白 R 脚本

## 依赖

[04-modules.md](./04-modules.md)。p 值计算规则与 [08-stats-workflows.md](./08-stats-workflows.md) 对齐。
