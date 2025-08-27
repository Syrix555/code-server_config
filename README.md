# code-server配置问题

## 为网站使用HTTPS连接
由于 http 连接不安全，根据 code-server 的设置，我们会无法使用一些功能（如扩展），必须为连接启用 HTTPS 连接，这就需要我们拥有一个域名，并且使用 Nginx + 证书配置反向代理为网站赋予 SSL 证书以便连接 HTTPS。

我们将使用 Nginx 来处理所有进来的网络请求，并使用 Certbot 来自动获取和续订由 Let's Encrypt 提供的免费 SSL 证书。

首先我们在云服务器上安装 Nginx 和Certbot （使用 apt 包管理器）：
```shell
sudo apt install nginx -y

sudo apt install certbot python3-certbot-nginx -y
```

接下来我们为 code-server 创建专用的配置文件：
```shell
sudo vim /etc/nginx/sites-available/code-server.conf
```
在文件内输入以下内容：
```conf
server {
    server_name code.my-domain.com; # <-- 修改成你的域名

    # 预留给 Certbot 的验证路径
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # 所有其他请求都反向代理到 code-server
    location / {
        proxy_pass http://127.0.0.1:6001; # <-- 修改成你的 code-server 地址和端口

        # --- WebSocket 支持 (非常重要！) ---
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        # --- WebSocket 支持结束 ---

        # --- 其他必要的头信息 ---
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        # --- 头信息结束 ---
    }

    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/code.my-domain.com/fullchain.pem;       # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/code.my-domain.com/privkey.pem;     # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf;                          # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;                            # managed by Certbot
}

server {
    if ($host = code.syrix.top) {
        return 301 https://$host$request_uri;
    } # managed by Certbot

    listen 80;
    server_name code.my-domain.com;
    return 404; # managed by Certbot
}
```

接下来创建一个从 sites-available 到 sites-enabled 的符号链接来启用这个配置。
```shell
sudo ln -s /etc/nginx/sites-available/code-server.conf /etc/nginx/sites-enabled/

sudo systemctl reload nginx
```

现在我们就可以通过域名访问我们的 code-server 了。

接着我们配置 certbot 以便获取证书并自动检测 Nginx 配置完成相关设置。
```shell
sudo certbot --nginx -d code.my-domain.com
```
完成一系列自动化任务后，我们就能够享用HTTPS连接了。

最后是证书自动续订的问题。由于certbot每次申请的证书的有效期是三个月，到期后我们可以通过自动续订程序完成。但需要有网站ICP备案才能通过域名访问互联网。

## 编辑器字体
由于 code-server 运行在本地电脑，而远程连接的设备对 code 窗口的渲染是在当前设备下进行的，因此在本地电脑上设置的字体在其他设备上就不会生效。而由于 code-server 由于微软的原因并没有提供一种便利的设置方法，需要我们自行向主页面 html 注入 css 以便网页渲染时调用本地静态资源。

这里的重点是我们应该向哪一个 html 注入 css ，注入什么内容的 css ，以及字体文件的存放位置。

通过官方的 readme 文件，我们可以知道主页面的html文件位于`/usr/lib/code-server/lib/vscode/out/vs/code/browser/workbench/workbench.html`，在这里注入 css。

我们需要注入的 css 内容如下：
```css
"<style id=custom-font-injection>
    @font-face {
      font-family: 'JetBrains Mono';
      font-style: normal;
      font-weight: 400;
      font-display: swap;
      src: url('_static/src/browser/pages/JetBrainsMono-Regular.woff2') format('woff2');
    }
    .monaco-editor, .xterm .xterm-rows {
        font-family: 'JetBrains Mono', monospace !important;
    }
</style>"
```

最重要的是我们应该把我们下载好的字体放在哪里，这里也是最麻烦的地方。通过查阅相关资料，我成功获取到了正确的位置。

根据这个回答([text](https://github.com/coder/code-server/issues/1374#issuecomment-1013967529)),我们的字体位置应该放在`/usr/local/lib/code-server/src/browser/pages`，而在 css 中我们应该写的 url 是：`_static/src/browser/pages/your-custom-font.woff2`，这样就能保证我们的字体能够全平台使用。

当然当我们更新 code-server 后我们`/usr/lib/code-server`下的自定义内容都会失效，我们就需要重新执行以上的内容，过于繁琐。因此我们可以增加一个 sh 脚本，作为 code-server 服务预启动需要执行的脚本，这样就可以在每次启动前将字体文件放到正确的位置并且注入 css，脚本内容在`apply-custom-css.sh`中。

用 sudo 权限编辑 code-server 服务的配置文件(`/etc/systemd/system/code-server.service`)，在`[service]`下增加这一行代码：
```ini
ExecStartPre=/bin/bash /home/syrix/apply-custom-css.sh
```
这样就可以在服务启动前自动处理字体配置。