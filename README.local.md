# Higress 本地网关

本目录是替换 Gravitee 后的新网关项目，基于 Higress Standalone `v2.2.1`。

## 本地地址

- Higress Console：http://localhost:8084
- Higress Gateway HTTP：http://localhost:8082
- Higress Gateway HTTPS：https://localhost:8443
- Gateway Metrics：http://localhost:15020
- Nacos Console：http://localhost:8888

默认管理账号：

```text
username: admin
password: admin
```

## 常用命令

```bash
./scripts/dev-up.sh
./scripts/status.sh
./scripts/logs.sh
./scripts/smoke-test.sh
./scripts/dev-down.sh
```

## 版本与开发隔离

`v1.0.0` 是光年AI 第一版发布基线。发布网关继续使用默认 `compose/` 和端口 `8082/8443/8084`，Cloudflare Tunnel 也继续只指向发布网关。

后续开发和测试在 `develop` 分支进行。需要独立网关时使用：

```bash
./scripts/dev-up-develop.sh
```

develop 网关会复制一份运行时配置到 `.runtime/develop/compose`，使用独立容器、端口和数据目录：

- Gateway HTTP：`http://localhost:18082`
- Gateway HTTPS：`https://localhost:18443`
- Console：`http://localhost:18084`
- Nacos Console：`http://localhost:18888`
- SSO develop：`http://sso-dev.localhost:18082`
- Image Gen develop：`http://image-dev.localhost:18082/image`

停止 develop 网关：

```bash
./scripts/dev-down-develop.sh
```

## 本机兼容说明

当前项目路径包含空格，官方 `bin/configure.sh` 有一处未加引号的重定向，已在本地修复。

本机 Docker Desktop 缺少 `docker-credential-desktop`，所以 `scripts/docker-env.sh` 会使用 `.docker-tmp` 作为干净的 `DOCKER_CONFIG`，避免拉镜像和 Compose 操作被全局 Docker 配置卡住。

macOS Docker Desktop 对绑定到宿主机共享目录的 Unix Socket 支持不稳定，Higress Gateway 的 `/var/run/secrets` 和 `/etc/istio/proxy` 已改为容器内 `tmpfs`，避免 gateway 启动时报 `operation not supported`。

`compose/.env` 包含本地生成的加密密钥，只保留在本机，不提交。
