import { copyFileSync, mkdirSync } from 'node:fs';
mkdirSync('public/images', {recursive:true});
for (const mode of ['light','dark']) copyFileSync(`../../assets/screenshots/library-${mode}.png`, `public/images/library-${mode}.png`);
copyFileSync('../../assets/icon/Previews/Default-512.png', 'public/cloakroll.png');
