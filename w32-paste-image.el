;;; w32-paste-image.el --- Paste image with cygwin emacs  -*- lexical-binding: t; -*-

;; Copyright (C) 2017  U-ITIHQ\Tobias.Zawada

;; Author: U-ITIHQ\Tobias.Zawada <Tobias.Zawada@smtp.1und1.de>
;; Keywords: docs, files, multimedia

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; 

;;; Code:

(require 'image)
(require 'cl-lib)
(require 'org) ;; for adding menu items to `org-org-menu'

(defvar-local w32-paste-image-hook nil "Run after pasting images from clipboard.")

(defvar-local w32-paste-image-prefix "" "Prefix to be inserted before the pasted image.")

(defvar-local w32-paste-image-dir-postfix "" "Postfix to be inserted at end of image directory.")

(defvar-local w32-paste-image-filename-prefix "img" "Prefix to be inserted before the pasted image.")

(defvar-local w32-paste-image-postfix "" "Postfix to be inserted after the pasted image.")

(defvar-local w32-paste-image-type "png" "Default image type and extension of pasted images.")

(unless (assoc "\\.eps" image-type-file-name-regexps)
  (add-to-list 'image-type-file-name-regexps '("\\.eps" . postscript)))

(defvar w32-paste-image-types
  '(
    ("png" nil nil '(image-mode))
    ("eps" "png" "convert %< -resample 100 -compress lzw ps3:%>" '(doc-view-mode))
    )
  "Each type specifier is a list. nth 0 is the target image format.
nth 1 is the source image format,
nth 2 is the converter from target to source %< stands for the source and %> stands for the output
nth 3 are lisp commands with which the image can be displayed"
  )

(defun w32-paste-image-get-pythonw-path ()
  "Try to determine the location of the python executable."
  (with-temp-buffer
    (catch :onError
      (when (eq (call-process "reg" nil t nil "query" "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\App Paths\\Python.exe") 1)
	(throw :onError ""))
      (goto-char (point-min))
      
      (unless (re-search-forward "\\<REG_SZ\\> *" nil t)
	(throw :onError ""))
      (cygwin-convert-file-name-from-windows
       (remove #xD ;; Carry-Return from DOS
	       (buffer-substring-no-properties (match-end 0) (line-end-position)))))))

(defun w32-paste-image-init-pythonw-path ()
  "Almost the same as `w32-paste-image-get-pythonw-path' but inform the user about initializing
`w32-paste-image-pythonw-interpreter'."
  (if (boundp 'w32-paste-image-pythonw-interpreter)
      w32-paste-image-pythonw-interpreter
    (let ((path (w32-paste-image-get-pythonw-path)))
      (message "Automagically setting `w32-paste-image-pythonw-interpreter' to \"%s\".
Change it per `customize-option' if you don't like that setting." path)
      path)))

(defcustom w32-paste-image-pythonw-interpreter (w32-paste-image-init-pythonw-path)
  "Python interpreter for retrieving images from the windows console.
Emacs tries to determine the value automatically at first customization but you can change it."
  :type 'string
  :group 'w32-paste-image)

(defun w32-paste-image-type-from-file-name (name)
  "Return image type for w32-paste-image"
  (car (assoc (downcase (file-name-extension name)) w32-paste-image-types)))

(defun w32-paste-image-paste (dir-name target-name img-type)
  (let*
      ((img-type-list (assoc img-type w32-paste-image-types))
       (grab-type (or (nth 1 img-type-list) (car img-type-list)))
       (converter (nth 2 img-type-list))
       (src-name target-name)
       )
    (unless (and (file-executable-p w32-paste-image-pythonw-interpreter)
		 (null (file-accessible-directory-p w32-paste-image-pythonw-interpreter)))
      (error "The setting `w32-paste-image-pythonw-interpreter'==\"%s\" is incorrect. Please, correct it before pasting images from the windows clipboard." w32-paste-image-pythonw-interpreter))
    (unless grab-type
      (error "Unsupported image grab type %s. (See w32-paste-image-types.)" img-type))
    (when converter
      (setq src-name (concat target-name "." grab-type)))
    (with-temp-buffer
      (setq default-directory dir-name)
      (insert "
from PIL import Image, ImageGrab
print \"--- Grab Image From Clipboard ---\"
im=ImageGrab.grabclipboard()
if isinstance(im,Image.Image):
 im.save(\"" src-name "\",\"" (upcase grab-type) "\")
else:
 print \"w32-paste-image-paste:No image in clipboard.\"
")
      (call-process-region (point-min) (point-max) w32-paste-image-pythonw-interpreter t t nil)
      (goto-char (point-min))
      (if (search-forward "w32-paste-image-paste:No image in clipboard." nil 'noError)
	  (error "No image in clipboard."))
      (message "%s" (buffer-substring-no-properties (point-min) (point-max)))
      (when converter
	(setq converter (replace-regexp-in-string "%<" src-name converter t t))
	(setq converter (replace-regexp-in-string "%>" target-name converter t t))
	(shell-command converter)
	(unless (equal src-name target-name)
	  (delete-file src-name))
	))
    ))

(defun w32-paste-image-absolute-dir-name ()
  (let ((bufi (buffer-file-name)))
    (concat (if bufi (file-name-sans-extension bufi) default-directory) w32-paste-image-dir-postfix)
    ))

(defun w32-paste-image-relative-dir-name ()
  (file-relative-name (w32-paste-image-absolute-dir-name) default-directory))

(defun w32-paste-image-cleanup ()
  "Remove pasted image files not contained in the document anymore."
  (interactive)
  (let* ((re-images (concat  w32-paste-image-filename-prefix "[0-9]*\\." w32-paste-image-type))
	 (dir-name (w32-paste-image-relative-dir-name))
	 (del-list (directory-files dir-name nil (concat "^" re-images "$") 'nosort)))
    (save-excursion
      (goto-char (point-min))
      (let ((re (concat dir-name "/\\(" re-images "\\)")))
	(while (search-forward-regexp re nil 'noErr)
	  (setq del-list (cl-delete (match-string-no-properties 1) del-list :test 'string-equal))
	  ))
      (cl-loop for f in del-list do
	    (let ((fullpath (concat dir-name "/" f)))
	      (with-temp-buffer
		(insert-file-contents fullpath)
		(set-buffer-modified-p nil)
		(eval (nth 3 (assoc w32-paste-image-type w32-paste-image-types)))
		(display-buffer (current-buffer))
		(when (yes-or-no-p (concat "Delete file " fullpath))
		  (delete-file fullpath)))))
      )))

(defun w32-paste-image-new-file-name (prefix suffix)
  "Get name of non-existing file by inserting numbers between PREFIX and SUFFIX if necessary.
SUFFIX may not include directory components."
  (let ((first-try (concat prefix suffix))
	(prefix-dir (or (file-name-directory prefix) "./"))
	(prefix-file (file-name-nondirectory prefix)))
    (if (file-exists-p first-try)
	(concat
	 prefix
	 (number-to-string
	  (1+
	   (apply
	    'max
	    (append '(-1)
		    (mapcar #'(lambda (name)
				(string-to-number (substring name (length prefix-file) (- (length suffix)))))
			    (directory-files prefix-dir nil (concat prefix-file "[0-9]+" suffix) 'NOSORT))))))
	 suffix)
      first-try)))


(defun w32-paste-image (&optional file-name img-type)
  "Paste image from windows clipboard into buffer.
That means put the image into the directory with the basename of the buffer file.
The image gets a name 'imgXXX.png' where XXX stands for some unique number."
  (interactive)
  (unless img-type
    (setq img-type w32-paste-image-type))
  (unless file-name
    (let* ((dir-name (w32-paste-image-absolute-dir-name))
	   (file-path (w32-paste-image-new-file-name (concat dir-name "/" w32-paste-image-filename-prefix) (concat "." img-type))))
      (setq dir-name (file-name-directory file-path))
      (setq file-name (file-name-nondirectory file-path))
      (while
	  (progn
	    (setq file-path (read-file-name "Image file name:" dir-name nil nil file-name))
	    (let ((dir (file-name-directory file-path)))
	      (or (and
		   dir
		   (file-exists-p dir)
		   (null (file-directory-p dir)))
		  (null (and (file-name-extension file-path)
			     (setq img-type (w32-paste-image-type-from-file-name file-path))))))))
      (setq file-name file-path)))
  (let* ((cur-dir default-directory)
	 (dir-name (or (file-name-directory file-name) "./"))
	 (dir-name-noslash (directory-file-name dir-name))
	 (fname (concat (file-name-nondirectory file-name)
			(if img-type
			    (if (string-match (concat "\\." w32-paste-image-type "$") file-name)
				""
			      (concat "." w32-paste-image-type))
			  (progn (setq img-type "png") ".png")))))
    (if (file-exists-p dir-name-noslash)
	(unless (file-directory-p dir-name-noslash)
	  (error "%s is not a directory" dir-name))
      (make-directory dir-name-noslash))
    (if img-type
	(if (symbolp img-type)
	    (setq img-type (symbol-name img-type)))
      (error "Image type not set."))
    (w32-paste-image-paste dir-name fname img-type)
    (insert w32-paste-image-prefix (file-relative-name dir-name cur-dir) fname w32-paste-image-postfix)
    (run-hooks 'w32-paste-image-hook)))

(global-set-key (kbd "C-S-y") 'w32-paste-image)

(defun w32-paste-image-setup-org ()
  "Implement prefix \"[[file:\", postfix \"]]\" and image updating in org-mode
for package w32-paste-image."
  (setq w32-paste-image-prefix "[[file:")
  (setq w32-paste-image-postfix"]]")
  (setq w32-paste-image-hook 'org-display-inline-images)
  (easy-menu-add-item org-org-menu '("Show/Hide") ["Toggle Show Images" org-toggle-inline-images t :help "Toggle Show Images"])
  )

(add-hook 'org-mode-hook #'w32-paste-image-setup-org)

(provide 'w32-paste-image)
;;; w32-paste-image.el ends here
