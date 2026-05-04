# Docker 一键部署

本文档用于把 `higress-api-gateway` 在一台新机器上用 Docker Compose 拉起。该项目是项目集群的统一入口网关，当前基于 Higress Standalone `v2.2.1`。

## 项目说明

网关负责把外部请求按域名、路径和方法转发到后端项目，并承载后续认证、鉴权、限流、IP 限制、请求屏蔽等统一入口能力。

本地默认路由：

| 域名 | 后端 |
| --- | --- |
| `sso.localhost` | `host.docker.internal:5173` |
| `sso-api.localhost` | `host.docker.internal:4000` |
| `image.localhost` | `host.docker.internal:3008` |

注意：Higress 容器内访问宿主机服务时，后端地址要写 `host.docker.internal`，不要写 `localhost`。

## 一键启动

在项目根目录执行：

```bash
./scripts/dev-up.sh
```

启动后访问：

| 服务 | 地址 |
| --- | --- |
| Higress Console | http://localhost:8084 |
| Higress Gateway HTTP | http://localhost:8082 |
| Higress Gateway HTTPS | https://localhost:8443 |
| Gateway Metrics | http://localhost:15020 |
| Nacos Console | http://localhost:8888 |

默认管理账号：

```text
username: admin
password: admin
```

## 写入项目集群路由

先确认 SSO 和 AI 生图应用已经在宿主机或 Docker 端口上监听：

```bash
curl -i http://localhost:5173/
curl -i http://localhost:4000/health
curl -i http://localhost:3008/api/health
```

然后写入本地路由：

```bash
./scripts/configure-ai-image-routes.sh
```

验证：

```bash
curl -i http://localhost:8082/ \
  -H 'Host: sso.localhost'

curl -i http://localhost:8082/health \
  -H 'Host: sso-api.localhost'

curl -i http://localhost:8082/api/health \
  -H 'Host: image.localhost'
```

浏览器访问：

```text
http://sso.localhost:8082
http://image.localhost:8082/image
```

## 常用操作

```bash
./scripts/status.sh
./scripts/logs.sh
./scripts/logs.sh gateway
./scripts/smoke-test.sh
./scripts/dev-down.sh
```

说明：

- `status.sh`：查看 Higress 各组件状态。
- `logs.sh`：查看全部日志，可追加服务名。
- `smoke-test.sh`：检查 Console 和 Gateway 欢迎页。
- `dev-down.sh`：停止 Higress。

## 服务来源配置口径

如果在 Console 手动配置后端服务：

| 字段 | 宿主机服务建议值 |
| --- | --- |
| 类型 | `DNS 域名 / DNS 服务（dns）` |
| 域名 / 服务地址 | `host.docker.internal` |
| 端口 | `5173`、`4000`、`3008` 等实际端口 |
| 协议 | `HTTP` |

不要把 `host.docker.internal` 填到 `固定地址 / static`，因为 static 只接受 IP 地址。如果 Console 报 `serviceSource body is not valid`，优先检查服务来源类型是否选错。

如果网关返回 `503` 且错误里有 `Connection refused`，通常表示路由已经命中，但上游端口没有服务在监听。先绕过网关直连 `localhost:<port>`，再回头查 Higress 路由。

## 数据与本机兼容

- `compose/.env` 会保存本机生成的密钥，不提交 Git。
- `compose/volumes/` 是 Higress/Nacos 运行数据，不提交 Git。
- `.docker-tmp/` 用于隔离本机 Docker 配置，避免全局 Docker credential 配置影响镜像拉取。
- 当前项目路径包含空格，仓库脚本已处理路径引用问题，建议继续用 `scripts/dev-up.sh` 这层入口，不直接调用底层 Compose 命令。

## 上线前检查

- 替换默认 `admin/admin`。
- 生产环境使用真实域名和 HTTPS。
- 把后端服务来源从本机 `host.docker.internal` 切换为内网 DNS、Kubernetes Service 或固定 IP。
- 给公开路由配置认证、限流和访问控制插件。
- 不要提交 `compose/.env`、运行卷和本地日志。

## Cloudflare Tunnel

公网暴露时只把 Cloudflare Tunnel 指向 Higress Gateway：

```text
Cloudflare Tunnel -> http://localhost:8082 -> Higress -> SSO / AI Image Studio
```

不要为 SSO API、SSO Web、AI 生图应用、MinIO 或 MySQL 单独创建公网 Tunnel。完整步骤见 [Cloudflare Tunnel 公网暴露方案](cloudflare-tunnel.md)。
