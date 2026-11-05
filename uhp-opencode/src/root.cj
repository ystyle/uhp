// uhp_opencode：opencode 2.x 的 UHP HarnessDriver 适配器。
//
// 定位：**消费方代码**。SDK（uhp-cj）只负责协议面，本仓负责把 opencode 的
// session/prompt/event 模型翻译成 UHP 的 TurnContext/TurnSink 语义。
//
// root.cj 只放包声明：driver 类型在根包，HTTP/SSE 辅助在 uhp_opencode.client 子包。
package uhp_opencode
