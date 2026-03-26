# OpenCode 自定义模型配置示例

下面给出一份适用于 OpenCode 的公司内网模型接入示例。

## 你的原始配置

你提供的片段如下：

```json
{
  "gongsi": {
    "api": "openai-completions",
    "options": {
      "baseURL": "http://llm.api.corp.qunar.com/v1",
      "apiKey": "YOUR_API_KEY"
    }
  }
}
```

这段配置思路是对的，但在 OpenCode 里不能直接这样写。

OpenCode 的自定义 Provider 需要放在 `provider` 下，并且通常要补齐以下字段：

- `npm`: 指定底层 Provider 适配器
- `name`: Provider 展示名称
- `options.baseURL`: 你的网关地址
- `options.apiKey`: API Key
- `models`: 显式声明模型列表
- `model`: 指定默认模型，格式为 `providerId/modelId`

## 推荐配置

请参考仓库中的 `opencode.json.example`。

最小可用写法如下：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "gongsi": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Gongsi",
      "options": {
        "baseURL": "http://llm.api.corp.qunar.com/v1",
        "apiKey": "{env:GONGSI_API_KEY}"
      },
      "models": {
        "REPLACE_WITH_REAL_MODEL_ID": {
          "name": "Gongsi Custom Model"
        }
      }
    }
  },
  "model": "gongsi/REPLACE_WITH_REAL_MODEL_ID"
}
```

## 为什么不是 `api: "openai-completions"`

根据 OpenCode 官方文档，自定义 OpenAI 兼容网关的推荐方式是：

- 使用自定义 provider id，例如 `gongsi`
- 通过 `npm: "@ai-sdk/openai-compatible"` 接入 OpenAI 兼容协议

也就是说，你原来这段：

```json
"api": "openai-completions"
```

在 OpenCode 自定义 provider 场景中，应该调整为：

```json
"npm": "@ai-sdk/openai-compatible"
```

## 安装/使用步骤

### 1. 准备配置文件

把 `opencode.json.example` 复制为以下任一位置的真实配置文件：

- 全局配置：`~/.config/opencode/opencode.json`
- 项目配置：项目根目录下的 `opencode.json`

### 2. 配置 API Key

不要把真实密钥直接写进 Git 仓库，推荐使用环境变量：

```bash
export GONGSI_API_KEY='你的真实 API Key'
```

### 3. 替换真实模型 ID

将配置中的：

```txt
REPLACE_WITH_REAL_MODEL_ID
```

替换成你们公司网关真实支持的模型 ID。

如果你不知道模型 ID，可以先调用模型列表接口确认，例如：

```bash
curl -s \
  -H "Authorization: Bearer $GONGSI_API_KEY" \
  "http://llm.api.corp.qunar.com/v1/models"
```

然后把返回结果里的模型名填到 `provider.gongsi.models` 和根节点 `model` 中。

### 4. 启动 OpenCode

```bash
opencode
```

进入后可以使用：

```txt
/models
```

选择 `gongsi/...` 下的模型。

也可以直接指定默认模型：

```bash
opencode -m gongsi/你的模型ID
```

## 注意事项

1. 当前 OpenCode 对自定义 OpenAI 兼容 Provider 通常需要显式声明模型，不能只配 `baseURL` 和 `apiKey`。
2. 如果你们公司网关只兼容 Chat Completions，而某些能力调用异常，需要进一步核对网关和 OpenCode 当前版本的兼容性。
3. 如果后续你能提供真实模型 ID，我可以直接帮你把示例改成最终可用版本。
