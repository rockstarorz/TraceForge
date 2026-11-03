# 参与维护

本仓库以 TraceForge V0.3.12.3 为公开协作基线。建议通过独立分支提交改动，不要把客户日志、设备标识或公司内部工具上传到仓库。

## 开发流程

```powershell
git switch -c feature/your-change
cd .\flutter_app
flutter pub get
flutter test
flutter run -d windows
```

提交前至少确认：

1. Flutter 单元测试通过。
2. Concox / GT06 示例日志仍能完成解析。
3. 时间轴、状态卡片与 KML 导出没有明显回归。
4. 原始日志模式相关改动使用本地 ProtocolAnalysis 做一次人工验证。

提交信息使用简洁英文，例如：

```text
fix: keep timeline cursor aligned after zoom
```

## Issue 建议格式

- 现象：看到了什么问题
- 影响：妨碍了什么排查工作
- 预期：希望软件如何表现
- 边界：本次只需要处理什么

日志请脱敏后截取最小可复现片段，禁止公开上传完整客户数据。
