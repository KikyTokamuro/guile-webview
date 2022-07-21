;;; guile-webview

;; MIT License

;; Copyright (c) 2022 Daniil Arkhangelsky (Kiky Tokamuro)

;; Permission is hereby granted, free of charge, to any person obtaining a copy
;; of this software and associated documentation files (the "Software"), to deal
;; in the Software without restriction, including without limitation the rights
;; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;; copies of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:

;; The above copyright notice and this permission notice shall be included in all
;; copies or substantial portions of the Software.

;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;; SOFTWARE.

(define-module (webview)
  #:use-module (system ffi-help-rt)
  #:use-module ((system foreign) #:prefix ffi:)
  #:use-module (bytestructures guile)
  #:export (webview-t
	    webview-t?
	    make-webview-t
	    webview-create
	    webview-destroy
	    webview-run
	    webview-terminate
	    webview-dispatch
	    webview-get-window
	    webview-set-title
	    webview-set-size
	    webview-navigate
	    webview-set-html
	    webview-init
	    webview-eval
	    webview-bind
	    webview-unbind
	    webview-return
	    ffi-webview-symbol-val
	    ffi-webview-types))

(define ffi-webview-llibs
  (delay (list (dynamic-link "libwebview"))))

;; typedef void *webview_t;
(define-public webview-t-desc (fh:pointer 'void))
(define-fh-pointer-type webview-t webview-t-desc webview-t? make-webview-t)

;; extern webview_t webview_create(int debug, void *window);
(define webview-create
  (let ((~webview-create
          (delay (fh-link-proc
                   ffi-void*
                   "webview_create"
                   (list ffi:int ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (debug window)
      (let ((~debug (unwrap~fixed debug))
            (~window (unwrap~pointer window)))
        ((fht-wrap webview-t)
         ((force ~webview-create) ~debug ~window))))))

;; extern void webview_destroy(webview_t w);
(define webview-destroy
  (let ((~webview-destroy
          (delay (fh-link-proc
                   ffi:void
                   "webview_destroy"
                   (list ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (w)
      (let ((~w ((fht-unwrap webview-t) w)))
        ((force ~webview-destroy) ~w)))))

;; extern void webview_run(webview_t w);
(define webview-run
  (let ((~webview-run
          (delay (fh-link-proc
                   ffi:void
                   "webview_run"
                   (list ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (w)
      (let ((~w ((fht-unwrap webview-t) w)))
        ((force ~webview-run) ~w)))))

;; extern void webview_terminate(webview_t w);
(define webview-terminate
  (let ((~webview-terminate
          (delay (fh-link-proc
                   ffi:void
                   "webview_terminate"
                   (list ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (w)
      (let ((~w ((fht-unwrap webview-t) w)))
        ((force ~webview-terminate) ~w)))))

;; extern void webview_dispatch(webview_t w, void (*fn)(webview_t w, void *arg), void *arg);
(define webview-dispatch
  (let ((~webview-dispatch
          (delay (fh-link-proc
                   ffi:void
                   "webview_dispatch"
                   (list ffi-void* ffi-void* ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (w fn arg)
      (let ((~w ((fht-unwrap webview-t) w))
            (~fn ((make-fctn-param-unwrapper
                    ffi:void
                    (list ffi-void* ffi-void*))
                  fn))
            (~arg (unwrap~pointer arg)))
        ((force ~webview-dispatch) ~w ~fn ~arg)))))

;; extern void *webview_get_window(webview_t w);
(define webview-get-window
  (let ((~webview-get-window
          (delay (fh-link-proc
                   ffi-void*
                   "webview_get_window"
                   (list ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (w)
      (let ((~w ((fht-unwrap webview-t) w)))
        ((force ~webview-get-window) ~w)))))

;; extern void webview_set_title(webview_t w, const char *title);
(define webview-set-title
  (let ((~webview-set-title
          (delay (fh-link-proc
                   ffi:void
                   "webview_set_title"
                   (list ffi-void* ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (w title)
      (let ((~w ((fht-unwrap webview-t) w))
            (~title (unwrap~pointer title)))
        ((force ~webview-set-title) ~w ~title)))))

;; extern void webview_set_size(webview_t w, int width, int height, int hints);
(define webview-set-size
  (let ((~webview-set-size
          (delay (fh-link-proc
                   ffi:void
                   "webview_set_size"
                   (list ffi-void* ffi:int ffi:int ffi:int)
                   (force ffi-webview-llibs)))))
    (lambda (w width height hints)
      (let ((~w ((fht-unwrap webview-t) w))
            (~width (unwrap~fixed width))
            (~height (unwrap~fixed height))
            (~hints (unwrap~fixed hints)))
        ((force ~webview-set-size)
         ~w
         ~width
         ~height
         ~hints)))))

;; extern void webview_navigate(webview_t w, const char *url);
(define webview-navigate
  (let ((~webview-navigate
          (delay (fh-link-proc
                   ffi:void
                   "webview_navigate"
                   (list ffi-void* ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (w url)
      (let ((~w ((fht-unwrap webview-t) w))
            (~url (unwrap~pointer url)))
        ((force ~webview-navigate) ~w ~url)))))

;; extern void webview_set_html(webview_t w, const char *html);
(define webview-set-html
  (let ((~webview-set-html
          (delay (fh-link-proc
                   ffi:void
                   "webview_set_html"
                   (list ffi-void* ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (w html)
      (let ((~w ((fht-unwrap webview-t) w))
            (~html (unwrap~pointer html)))
        ((force ~webview-set-html) ~w ~html)))))

;; extern void webview_init(webview_t w, const char *js);
(define webview-init
  (let ((~webview-init
          (delay (fh-link-proc
                   ffi:void
                   "webview_init"
                   (list ffi-void* ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (w js)
      (let ((~w ((fht-unwrap webview-t) w))
            (~js (unwrap~pointer js)))
        ((force ~webview-init) ~w ~js)))))

;; extern void webview_eval(webview_t w, const char *js);
(define webview-eval
  (let ((~webview-eval
          (delay (fh-link-proc
                   ffi:void
                   "webview_eval"
                   (list ffi-void* ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (w js)
      (let ((~w ((fht-unwrap webview-t) w))
            (~js (unwrap~pointer js)))
        ((force ~webview-eval) ~w ~js)))))

;; extern void webview_bind(webview_t w, const char *name, void (*fn)(const char *seq, const char *req, void *arg), void *arg);
(define webview-bind
  (let ((~webview-bind
          (delay (fh-link-proc
                   ffi:void
                   "webview_bind"
                   (list ffi-void* ffi-void* ffi-void* ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (w name fn arg)
      (let ((~w ((fht-unwrap webview-t) w))
            (~name (unwrap~pointer name))
            (~fn ((make-fctn-param-unwrapper
                    ffi:void
                    (list ffi-void* ffi-void* ffi-void*))
                  fn))
            (~arg (unwrap~pointer arg)))
        ((force ~webview-bind) ~w ~name ~fn ~arg)))))

;; extern void webview_unbind(webview_t w, const char *name);
(define webview-unbind
  (let ((~webview-unbind
          (delay (fh-link-proc
                   ffi:void
                   "webview_unbind"
                   (list ffi-void* ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (w name)
      (let ((~w ((fht-unwrap webview-t) w))
            (~name (unwrap~pointer name)))
        ((force ~webview-unbind) ~w ~name)))))

;; extern void webview_return(webview_t w, const char *seq, int status, const char *result);
(define webview-return
  (let ((~webview-return
          (delay (fh-link-proc
                   ffi:void
                   "webview_return"
                   (list ffi-void* ffi-void* ffi:int ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (w seq status result)
      (let ((~w ((fht-unwrap webview-t) w))
            (~seq (unwrap~pointer seq))
            (~status (unwrap~fixed status))
            (~result (unwrap~pointer result)))
        ((force ~webview-return) ~w ~seq ~status ~result)))))

;; Access to enum symbols and #define'd constants:
(define ffi-webview-symbol-tab
  '((WEBVIEW-HINT-FIXED . 3)
    (WEBVIEW-HINT-MAX . 2)
    (WEBVIEW-HINT-MIN . 1)
    (WEBVIEW-HINT-NONE . 0)))

(define ffi-webview-symbol-val
  (lambda (k)
    (or (assq-ref ffi-webview-symbol-tab k))))

(define (unwrap-enum obj)
  (cond ((number? obj) obj)
        ((symbol? obj) (ffi-webview-symbol-val obj))
        ((fh-object? obj) (struct-ref obj 0))
        (else (error "type mismatch"))))

(define ffi-webview-types '("webview_t"))
