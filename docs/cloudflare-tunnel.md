# Cloudflare Tunnel 公网暴露方案

目标：公网只暴露 Cloudflare Tunnel 到 Higress Gateway，SSO、AI 生图、MySQL、MinIO 等服务不直接暴露公网端口。Cloudflare 负责公网入口，Higress 负责本机反向代理和业务路由。

## 推荐域名

准备三个公网 Host，全部指向同一个 Tunnel，本机服务统一落到 `http://localhost:8082`：

| 公网 Host | Cloudflare Tunnel service | Higress 后端 |
| --- | --- | --- |
| `sso.example.com` | `http://localhost:8082` | `host.docker.internal:5173` |
| `sso-api.example.com` | `http://localhost:8082` | `host.docker.internal:4000` |
| `image.example.com` | `http://localhost:8082` | `host.docker.internal:3008` |

也可以不用 `sso-api.example.com`，但保留它方便公网健康检查和 OIDC/API 调试。

## 1. 登录 Cloudflare

```bash
cloudflared tunnel login
```

登录成功后，本机会生成 `~/.cloudflared/cert.pem`。

## 2. 创建命名 Tunnel

```bash
cloudflared tunnel create project-cluster
cloudflared tunnel list
```

记下 Tunnel UUID。Cloudflare 会在 `~/.cloudflared/<TUNNEL_UUID>.json` 生成凭据文件。

## 3. 写入 DNS 路由

把下面的域名换成你的真实域名：

```bash
cloudflared tunnel route dns project-cluster sso.example.com
cloudflared tunnel route dns project-cluster sso-api.example.com
cloudflared tunnel route dns project-cluster image.example.com
```

## 4. 配置 cloudflared

创建或更新 `~/.cloudflared/config.yml`：

```yaml
tunnel: <TUNNEL_UUID>
credentials-file: /Users/luoyunlong/.cloudflared/<TUNNEL_UUID>.json

ingress:
  - hostname: sso.example.com
    service: http://localhost:8082
  - hostname: sso-api.example.com
    service: http://localhost:8082
  - hostname: image.example.com
    service: http://localhost:8082
  - service: http_status:404
```

校验路由匹配：

```bash
cloudflared tunnel ingress rule https://image.example.com/api/health
```

## 5. 以公网域名启动业务容器

SSO 的 OIDC issuer 必须使用公网域名：

```bash
cd ../sso-user-system
DOCKER_WEB_ORIGIN=https://sso.example.com \
DOCKER_OIDC_ISSUER=https://sso.example.com/oidc \
DOCKER_GITHUB_OAUTH_CALLBACK_URL=https://sso.example.com/auth/github/callback \
DOCKER_AI_IMAGE_GATEWAY_REDIRECT_URI=https://image.example.com/oauth/callback \
npm run docker:up
```

AI 生图应用也必须使用公网回调地址：

```bash
cd ../ai-image-studio
AI_IMAGE_DEV_AUTH_BYPASS=false \
AI_IMAGE_APP_ORIGIN=https://image.example.com \
AI_IMAGE_SSO_ISSUER=https://sso.example.com/oidc \
AI_IMAGE_SSO_REDIRECT_URI=https://image.example.com/oauth/callback \
AI_IMAGE_SSO_PROFILE_URL=https://sso.example.com/profile \
AI_IMAGE_SSO_INTERNAL_BASE_URL=http://host.docker.internal:4000 \
AI_IMAGE_SSO_CREDIT_USAGE_URL=http://host.docker.internal:4000/internal/credits/usage \
AI_IMAGE_SSO_JOB_LOGS_URL=http://host.docker.internal:4000/internal/application-job-logs \
npm run docker:up
```

## 6. 写入 Higress 公网 Host

```bash
cd ../higress-api-gateway
PUBLIC_SSO_HOST=sso.example.com \
PUBLIC_SSO_API_HOST=sso-api.example.com \
PUBLIC_IMAGE_HOST=image.example.com \
./scripts/configure-ai-image-routes.sh
```

这一步只是在 Higress 里增加公网 Host 的 Ingress；后端仍然是本机端口，不会直接暴露 SSO 或生图服务。

## 7. 启动 Tunnel

前台运行：

```bash
cloudflared tunnel run project-cluster
```

作为 macOS 登录项运行：

```bash
cloudflared service install
```

## 8. 验证

```bash
curl -i https://sso.example.com/
curl -i https://sso-api.example.com/health
curl -i https://sso.example.com/oidc/.well-known/openid-configuration
curl -i https://image.example.com/api/health
```

## 安全边界

- Cloudflare Tunnel 的 service 只写 `http://localhost:8082`。
- 不要给 `localhost:4000`、`localhost:5173`、`localhost:3008`、`localhost:9000`、`localhost:3307` 创建公网 Tunnel。
- 生产使用 HTTPS 域名作为 OIDC issuer 和 OAuth redirect URI。
- 后续认证、限流、访问控制插件统一放在 Higress。
