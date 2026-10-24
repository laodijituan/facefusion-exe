# -*- mode: python ; coding: utf-8 -*-
"""
PyInstaller spec for FaceFusion (onedir, portable).

Environment variables:
  FF_SRC      path to the FaceFusion source checkout        (default: src/facefusion)
  FF_VARIANT  cpu | cuda12 | directml                       (default: cpu)  -> naming only
  FF_CUDA_DIR optional: site-packages/nvidia  (enable CUDA dll bundling)
"""

import glob
import os

from PyInstaller.utils.hooks import collect_all, collect_dynamic_libs, collect_submodules

SRC = os.path.abspath(os.environ.get('FF_SRC', 'src/facefusion'))
VARIANT = os.environ.get('FF_VARIANT', 'cpu').strip() or 'cpu'
CUDA_DIR = os.environ.get('FF_CUDA_DIR', '').strip()
APP_NAME = 'FaceFusion'

print(f'[spec] source   = {SRC}')
print(f'[spec] variant  = {VARIANT}')
print(f'[spec] cuda dir = {CUDA_DIR or "-"}')

datas = []
binaries = []
hiddenimports = []

# ---------------------------------------------------------------------------
# FaceFusion itself.
# The source tree is shipped *as data* on purpose: FaceFusion discovers its
# processors and UI layouts by listing directories at runtime
# (resolve_file_paths('facefusion/processors/modules')), which is impossible
# from inside the PYZ archive.  The .py files are also kept so that
# `__file__`-relative lookups (.assets/models, uis/assets/overrides.css) work.
# ---------------------------------------------------------------------------
datas.append((os.path.join(SRC, 'facefusion'), 'facefusion'))
datas.append((os.path.join(SRC, 'facefusion.ini'), '.'))
datas.append((os.path.join(SRC, 'LICENSE.md'), '.'))

# dynamic `importlib.import_module('facefusion.uis.layouts.' + name)` calls.
# FaceFusion is not a pip package, so it has to be importable from the build
# environment before collect_submodules() can walk it.
import sys

if SRC not in sys.path:
	sys.path.insert(0, SRC)

hiddenimports += collect_submodules('facefusion')

for root_dir, _, file_names in os.walk(os.path.join(SRC, 'facefusion')):
	for file_name in file_names:
		if file_name.endswith('.py'):
			module_path = os.path.relpath(os.path.join(root_dir, file_name), SRC)[:-3].replace(os.sep, '.')
			if module_path.endswith('.__init__'):
				module_path = module_path[:-len('.__init__')]
			hiddenimports.append(module_path)

# ---------------------------------------------------------------------------
# gradio ships no PyInstaller hook: collect the whole package, including the
# prebuilt frontend under gradio/templates/.
# ---------------------------------------------------------------------------
for package in ( 'gradio', 'gradio_client', 'gradio_rangeslider', 'safehttpx', 'groovy', 'semantic_version', 'multipart', 'fastapi', 'starlette', 'uvicorn', 'anyio', 'httpx', 'jinja2', 'markupsafe', 'pydantic', 'pydantic_core', 'websockets', 'aiofiles', 'python_multipart', 'pandas', 'PIL', 'tomlkit', 'typer', 'pydub', 'ffmpy', 'orjson', 'rich', 'click', 'shellingham', 'typing_extensions' ):
	try:
		package_datas, package_binaries, package_hidden_imports = collect_all(package)
		datas += package_datas
		binaries += package_binaries
		hiddenimports += package_hidden_imports
	except Exception as exception:  # noqa: BLE001 - optional packages
		print(f'[spec] skip {package}: {exception}')

# onnxruntime providers (CUDA / DirectML / CPU) live in separate DLLs
binaries += collect_dynamic_libs('onnxruntime')

# ---------------------------------------------------------------------------
# Optional CUDA 12 runtime (cuDNN 9 + cuBLAS + cudart) so the GPU build does
# not require a local CUDA toolkit installation.
# ---------------------------------------------------------------------------
if CUDA_DIR and os.path.isdir(CUDA_DIR):
	found = 0
	for dll in glob.glob(os.path.join(CUDA_DIR, '**', '*.dll'), recursive = True):
		binaries.append((dll, '.'))
		found += 1
	print(f'[spec] bundled {found} CUDA runtime dlls from {CUDA_DIR}')

hiddenimports += [ 'uvicorn.logging', 'uvicorn.loops.auto', 'uvicorn.protocols.http.auto', 'uvicorn.protocols.websockets.auto', 'uvicorn.lifespan.on' ]

a = Analysis(
	[ 'launcher.py' ],
	pathex = [ SRC ],
	binaries = binaries,
	datas = datas,
	hiddenimports = sorted(set(hiddenimports)),
	hookspath = [ ],
	hooksconfig = { },
	runtime_hooks = [ ],
	excludes = [ 'tkinter', 'matplotlib', 'torch', 'torchvision', 'tensorflow', 'IPython', 'notebook', 'pytest', 'setuptools._distutils' ],
	noarchive = False,
	optimize = 0,
)
pyz = PYZ(a.pure)

exe = EXE(
	pyz,
	a.scripts,
	[ ],
	exclude_binaries = True,
	name = APP_NAME,
	debug = False,
	bootloader_ignore_signals = False,
	strip = False,
	upx = False,
	upx_exclude = [ ],
	runtime_tmpdir = None,
	console = True,
	icon = os.path.join(SRC, 'facefusion.ico') if os.path.isfile(os.path.join(SRC, 'facefusion.ico')) else None,
	contents_directory = '.',  # flat portable layout: no _internal/ wrapper
)

coll = COLLECT(
	exe,
	a.binaries,
	a.datas,
	strip = False,
	upx = False,
	upx_exclude = [ ],
	name = APP_NAME,
)
