// 渲染测试:用 Go text/template 渲染 docker-compose.yaml,钉住安装期渲染事故。
// 本地: go run scripts/test-compose-template.go ;CI 的 build job 也会跑。
//
// 背景真机坑(ugos-pro-app-dev skill):
//   - 渲染发生在安装时,本地 pack 完全测不出来,只能靠这类测试钉住
//   - 本文件的 compose 只用内置标量 TZ(平台必注入),没有 parameters;
//     镜像 tar 打包进 upk,不需要镜像加速变量,也不允许出现美元符
//     (ugcli 扫描未声明参数的 VAR 会报"变量未设置",check 直接挂)
package main

import (
	"os"
	"strings"
	"text/template"
)

func render(tpl *template.Template, data any) string {
	var sb strings.Builder
	if err := tpl.Execute(&sb, data); err != nil {
		panic("渲染失败: " + err.Error())
	}
	return sb.String()
}

func assert(cond bool, msg string) {
	if !cond {
		println("FAIL: " + msg)
		os.Exit(1)
	}
}

func main() {
	raw, err := os.ReadFile("com.rachelos.wemprss/rootfs_common/docker-compose.yaml")
	if err != nil {
		panic(err)
	}
	tpl, err := template.New("compose").Parse(string(raw))
	if err != nil {
		panic("模板解析失败: " + err.Error())
	}

	// 场景 1:平台正常注入 TZ
	r1 := render(tpl, map[string]any{"TZ": "Asia/Shanghai"})

	// 场景 2:键整个缺失(万一平台没注入,渲染也不能崩)
	r2 := render(tpl, map[string]any{})

	for i, r := range []string{r1, r2} {
		tag := string(rune('1' + i))
		assert(!strings.Contains(r, "{{"), "场景"+tag+" 残留模板占位符")
		assert(!strings.Contains(r, "$"), "场景"+tag+" 出现美元符(ugcli 变量扫描会拒)")
		assert(strings.Contains(r, `image: "ghcr.io/rachelos/we-mp-rss:1.5.3"`), "场景"+tag+" 镜像引用不对")
		assert(strings.Contains(r, `"28001:8001"`), "场景"+tag+" 端口映射丢失")
		assert(strings.Contains(r, "./data:/app/data:rw"), "场景"+tag+" 数据卷丢失")
	}
	assert(strings.Contains(r1, `TZ: "Asia/Shanghai"`), "场景1 TZ 未渲染")

	println("PASS: 2 个场景渲染全部通过")
}
