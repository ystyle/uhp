// uhp_acp：ACP（Agent Client Protocol）的 UHP HarnessDriver 适配器。
//
// 定位：消费方代码。SDK（uhp-cj）负责协议面；ACP 库（acp-cj）负责 JSON-RPC over stdio；
// 本仓只做「ACP session/update ↔ UHP TurnSink」的翻译。
package uhp_acp
