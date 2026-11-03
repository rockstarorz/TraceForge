# TRACEFORGE 官方解析桥接

发布包中请将 `official_bridge.exe`、`ProtocolAnalysis.exe` 与 `TraceForge.exe` 放在同一目录。

桥接仅在本机控制官方解析工具，不进行 IP 授权或网络验证。临时输入与结果写入 Windows 临时目录，供 TRACEFORGE 在本次解析中读取。

本地运行桥接源码时，需要 Python 与 `requirements.txt` 中的依赖；可用环境变量 `OFFICIAL_BRIDGE_PYTHON` 和 `PROTOCOL_ANALYSIS_EXE` 指定程序位置。
