// UHP SDK 的唯一入口包：只做 public import，不承载实现。
//
// 依赖方向：codec <- base <- generated <- handwritten <- transport <- client/server
// 这里按层聚合导出，调用方只需 import uhp.* 即可拿到类型与传输组件。
package uhp

public import uhp.types.*
public import uhp.transport.*
