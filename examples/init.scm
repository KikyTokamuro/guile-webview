(add-to-load-path
 (string-append (dirname (current-filename)) "/../"))

(use-modules (webview))

(define wv (webview-create 1 (make-webview-t)))
(webview-set-title wv "Init")
(webview-set-html wv "Hello World")
(webview-set-size wv 500 500 0)
(webview-run wv)
