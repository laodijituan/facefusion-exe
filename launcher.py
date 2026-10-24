#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FaceFusion portable EXE launcher.

Responsibilities (all of them are needed for a frozen build):
  1. make the whole bundle folder self-contained: put the folder itself on PATH
     so the bundled ffmpeg.exe / ffprobe.exe / curl.exe get found first;
  2. chdir into the bundle folder, because FaceFusion enumerates its own
     modules with relative paths ('facefusion/processors/modules',
     'facefusion/uis/layouts');
  3. make model downloads / jobs / outputs land next to the exe instead of
     inside a temporary extraction folder;
  4. default to `run --open-browser` when no arguments were given.
"""

import multiprocessing
import os
import sys


def get_app_root() -> str:
	if getattr(sys, 'frozen', False):
		return os.path.dirname(os.path.abspath(sys.executable))
	return os.path.dirname(os.path.abspath(__file__))


def bootstrap() -> str:
	app_root = get_app_root()

	# 1. bundled ffmpeg / ffprobe / curl win over anything on the system
	os.environ['PATH'] = app_root + os.pathsep + os.environ.get('PATH', '')

	# 2. quiet, offline friendly runtime
	os.environ.setdefault('GRADIO_ANALYTICS_ENABLED', 'False')
	os.environ.setdefault('GRADIO_SSR_MODE', 'False')
	os.environ.setdefault('OMP_NUM_THREADS', '1')
	os.environ.setdefault('PYTHONUTF8', '1')
	os.environ.setdefault('PYTHONIOENCODING', 'utf-8')
	os.environ.setdefault('PYTHONLEGACYWINDOWSSTDIO', '0')

	# 3. FaceFusion resolves a lot of things relative to the CWD
	try:
		os.chdir(app_root)
	except OSError:
		pass

	return app_root


def main() -> None:
	multiprocessing.freeze_support()
	app_root = bootstrap()

	args = sys.argv[1:]

	if not args:
		args = [ 'run', '--open-browser' ]
	elif not args[0].startswith('-') and args[0] not in ( 'run', 'headless-run', 'batch-run', 'force-download', 'benchmark', 'job-list', 'job-create', 'job-submit', 'job-submit-all', 'job-delete', 'job-delete-all', 'job-add-step', 'job-remix-step', 'job-insert-step', 'job-remove-step' ):
		# a bare file path was given -> treat it as `run <file> ...`
		args = [ 'run' ] + args

	program_name = 'FaceFusion.exe' if os.name == 'nt' else 'FaceFusion'
	sys.argv = [ os.path.join(app_root, program_name) ] + args

	os.makedirs(os.path.join(app_root, '.assets', 'models'), exist_ok = True)
	os.makedirs(os.path.join(app_root, '.jobs'), exist_ok = True)
	os.makedirs(os.path.join(app_root, 'output'), exist_ok = True)

	from facefusion import conda, core

	conda.setup()
	core.cli()


if __name__ == '__main__':
	main()
