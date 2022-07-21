(add-to-load-path
 (string-append (dirname (current-filename)) "/../"))

(use-modules (webview))

(define wv (webview-create 1 (make-webview-t)))
(webview-set-title wv "Url")
(webview-navigate wv "https://www.gnu.org/software/guile/")
(webview-set-size wv 800 500 0)
(webview-run wv)
