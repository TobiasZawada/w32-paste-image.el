Installation
===

Put `w32-paste-image.el` into your `load-path`, add `(require 'w32-paste-image)` to your init file and restart emacs.

You should customize the option `w32-paste-image-pythonw-interpreter` after installation of `w32-paste-image`.
Maybe, your python interpreter is detected automatically. Save the variable customization anyway.
That prevents emacs from automatic detection next time.

Usage
===
1. Copy some image to the windows clipboard
2. Go to some emacs org-file, put point to where the image should be pasted and press <kbd>C-S-y</kbd>.
