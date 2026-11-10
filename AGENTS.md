# uhp monorepo 约定

> 工作区通用约定见 [../AGENTS.md](../AGENTS.md)；成员各自的约定见 `uhp/AGENTS.md`。
> 冲突时：成员文件 > 本文件 > 工作区文件。

## 1. 布局

```text
uhp/                    产品根（本文件、cjpm.toml workspace、workspace.toml）
├── uhp/                SDK 成员：协议面 + 服务端骨架 + HarnessDriver SPI
├── uhp-opencode/       opencode 2.x 适配器（可安装的发布成员）
├── uhp-acp/            ACP 通用适配器（可安装的发布成员）
├── scripts/            产品级命令（build / test）
└── target/             构建产物（workspace 统一输出）
```

- 成员间依赖写版本号（`"uhp" = "0.1.0"`），由 workspace 解析到本地成员；不写 path 依赖。
- 依赖方向：**适配器 → SDK**，单向。SDK 不认识任何适配器。
- 三个成员共用一份 `cjpm.lock`（根目录）。

## 2. 命令（在仓库根执行）

```bash
eval "$(cjvs env zsh)" && eval "$(cjvs stdx-env zsh)"
bash scripts/build.sh          # cjpm build -j 8（全部成员）
bash scripts/test.sh           # cjpm build + cjpm test -j 4（全部成员）
```

- workspace 测试要起真实子进程（ACP 假 agent、本地 HTTP 服务），**一律 -j 4**；-j 16 会拖死。
- 只验证一个成员时：cd uhp && cjpm test -j 4 --no-progress。
- CLI 过滤用例：--filter '*keyword*'（通配符不是正则；顶层 @Test func 没有点）。

## 3. 边界

- **SDK 夹带消费方代码是反向依赖**：不要往 `uhp/src` 里加任何 specific agent 的适配逻辑。
  真实适配器只放在 `uhp-opencode/`、`uhp-acp/` 这类成员里，通过 `HarnessDriver` 接缝接入。
- 新增适配器 = 新增一个 workspace 成员；发布与否是**显式决策**：默认与其它成员一起发布（列进 `workspace.toml` 的 [workspace.publish]），本仓要放弃发布时必须写明理由并在这里记一条。
- 适配器可以依赖第三方协议库（如 acp），但 SDK **不许**依赖它们。

## 4. 测试与真实链路

- 默认测试不依赖网络/付费模型：适配器测试用**同进程假服务端**或**本仓内置假 agent 子进程**。
- 真实链路冒烟走 */scripts/real-smoke.sh，需要本机凭据与模型，**不进默认 CI**。
- 新行为必须有测试；测试发现的问题先加会红的用例再修。

## 5. 文档

- 成员内 docs/ 随成员演进；SDK 的 uhp/docs/support.md 是实现边界的单一事实来源。
- 未实现就写「未实现」，不要用「计划支持」冒充现状。

## 6. 发版

- 产品版本在 workspace.toml（[workspace.package] version）；**三个成员统一发布**，版本由 [workspace.package] 统一推进。
- 三个成员都是中心仓可安装包（`uhp` / `uhp_opencode` / `uhp_acp`），版本与 `uhp` 同步推进，不存在「只发 SDK」的单独发版。
- 走工作区闸门：`./scripts/workspace-release.sh check uhp`（dry-run 预演）→ 私有仓预演 → 中心仓（脚本只认预演仓；中心仓按 cangjie-publish skill 手工发）。
- 适配器依赖在中心仓必须按版本解析：`uhp_acp` 依赖 `uhp` + `acp` + `ystyle::jsonrpc`，`uhp_opencode` 依赖 `uhp`，发布顺序 SDK 先、适配器后（索引同步后）。
- 发版前必须：bash scripts/test.sh 绿 + 三档一致性报告刷新 + 制品解包核对（见工作区 docs/publish-scope.md）。
