import { readFile } from 'node:fs/promises';
import { WASI } from 'node:wasi';
import { argv } from 'node:process';
const wasi = new WASI({ version: 'preview1', args: ['e16host', ...argv.slice(3)], preopens: { '/': '/' } });
const mod = await WebAssembly.compile(await readFile(argv[2]));
const inst = await WebAssembly.instantiate(mod, wasi.getImportObject());
wasi.start(inst);
