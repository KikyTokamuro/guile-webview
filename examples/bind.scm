(add-to-load-path
 (string-append (dirname (current-filename)) "/../"))

(use-modules (webview)
	     (system foreign)
	     (json))

(define (js-sum seq req arg)
  (let* ((args (json-string->scm (pointer->string req)))
	 (arg1 (vector-ref args 0))
	 (arg2 (vector-ref args 1)))
    (webview-return wv seq 0 (scm->json-string (+ arg1 arg2)))))

(define wv (webview-create 1 (make-webview-t)))

(webview-set-title wv "Bind")
(webview-set-html wv "")
(webview-set-size wv 800 500 0)
(webview-bind wv "sum" js-sum 0)
(webview-init wv "sum(1, 2).then((r) => alert(r))")
(webview-run wv)
