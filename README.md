# WeRSS 微信公众号订阅助手 · 绿联 UGOS Pro 应用

把 [rachelos/we-mp-rss](https://github.com/rachelos/we-mp-rss)(微信公众号 RSS 订阅助手)打包成绿联 UGOS Pro 的 **Docker 型应用**,并带 GitHub Actions 自动跟上游版本打包发版。

## 为什么是 Docker 型应用

上游是 Python 3.13 + FastAPI,采集走 Playwright(webkit/chromium 双浏览器)+ Xvfb,还内置一个 Node 级联服务和一个内部 Redis——上游唯一发行形态就是双架构 Docker 镜像。这种「解释型 + 浏览器自动化」组合打成原生应用,要么砍掉浏览器采集(核心功能),要么塞 2.5 GB 运行时进沙箱还赌 Playwright 在受限沙箱里能起浏览器。Docker 型应用直接使用上游镜像,功能与上游 100% 一致,这也是绿联为这类应用设计的标准形态。

两个实测出来的硬约束:

- **ugcli 要求镜像 tar 打进包里**:`rootfs_<arch>/images/<镜像名>-<tag>.tar`(docker save 产物,check 会真的解析 manifest.json),不支持纯远程镜像引用。所以每个 upk 约 1.7 GB——代价是**安装时不联网拉镜像**,ghcr.io 通不通都无所谓。
- **compose 里不能出现美元符**:ugcli 扫描 compose 里的 `$VAR`,凡未在 parameters 声明的一律报「变量未设置」,连 `$$` 转义都逃不掉。本项目 compose 无任何参数,只用内置标量 TZ。

## 安装

1. 应用中心 → 手动安装 → 选对应架构的 upk(amd64 / arm64,Releases 页下载,每架构约 1.7 GB)
2. 打开应用 → 登录页:默认账号 `admin`,初始密码 `admin@123`,**登录后立即修改**
3. 在网页里扫码授权公众号、添加订阅,RSS 链接喂给任意阅读器

- 端口:28001(不照抄上游 8001,避免和已有 Docker 版撞车)
- 数据:应用安装目录下的 `data/`(数据库、缓存、授权凭据、会话密钥),升级/迁移跟着应用走
- 会话密钥:上游在 `SECRET_KEY` 未设置时自动生成强随机密钥持久化到 `data/.secret_key`,无需配置
- 镜像:`ghcr.io/rachelos/we-mp-rss:<version>`,已离线打进 upk

## 自动构建(GitHub Actions)

`build.yml` 三条触发路径:

| 触发 | 行为 |
|---|---|
| push(应用目录/脚本/工具链) | 打包发版;该版本已有 tag 则跳过 |
| 手动 dispatch | 修订重发:同版本构建号 +1,旧 Release 自动清理 |
| 每日 09:00(北京时间) | 查上游最新 release,出新版自动 bump 版本 → 提交 → 打包发版 |

- build job 按架构并行:`docker pull --platform <arch>` → `docker save` 进 images/ → 渲染测试 → `ugcli check` + `pack`
- 构建号 = 已有 `upk-*` tag 最大序号 + 1,只升不降(ugcli 同版本构建号必须递增)
- `tools/ugcli/` 内置 Linux 版 ugcli,不依赖绿联 CDN(海外 runner 常连不上)
- CI 诡异行为先查 <https://www.githubstatus.com> 的 Actions 状态,别先怀疑自己的配置

## 本地打包

```sh
# 1) 准备镜像 tar(上游只发 latest:拉下来 retag 成版本号再 save)
VERSION=1.5.3
for A in amd64 arm64; do
  docker pull --platform linux/$A ghcr.io/rachelos/we-mp-rss:latest
  docker tag ghcr.io/rachelos/we-mp-rss:latest ghcr.io/rachelos/we-mp-rss:$VERSION
  docker save ghcr.io/rachelos/we-mp-rss:$VERSION \
    -o com.rachelos.wemprss/rootfs_$A/images/we-mp-rss-$VERSION.tar
done

# 2) 渲染测试 + 打包
go run scripts/test-compose-template.go
scripts/build.sh 1                # 构建号 1,amd64 + arm64
scripts/build.sh 2 amd64          # 单架构重打

# 3) 查上游最新版本
eval "$(scripts/get-latest-version.sh)"
```

产物:`./com.rachelos.wemprss_<版本>.upk`(构建号四位补零)。mac 上跑 `ugcli check/pack` 用的是 darwin 版二进制(`~/bin/ugcli`),CI 用 `tools/ugcli/` 里的 Linux 版。

## 上游已知行为(打包时注意到,非本包引入)

- **只发 `:latest` 一个 tag**:没有版本 tag。本包在构建时把 latest 拉下来 retag 成上游 release 版本号打进包;CI 里按 detect 阶段解析的 per-arch digest 钉住内容,避免 bump 与构建之间上游换镜像的竞态
- 容器启动时 `main.py` 会把全部环境变量打进 stdout(容器日志仅管理员可见)
- 上游 Dockerfile 里 `PLAYWRIGHT_BROWSERS_PATH` 硬编码 `_x86_64` 后缀,arm64 镜像的浏览器路径是否一致取决于上游构建方式——arm64 机器上若浏览器采集异常,先查容器里 `/app/env/driver/` 实际目录名

## 许可

上游 we-mp-rss 采用 [MIT License](https://github.com/rachelos/we-mp-rss/blob/main/LICENSE)(Copyright (c) 2025 RACHEL)。打包工程同以 MIT 发布,见 LICENSE。
