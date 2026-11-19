// Exécute les fichiers SQL du projet sur la base Supabase (ou n'importe quel Postgres).
//
//   npm run db:seed     -> vide les tables et les remplit avec seed.sql
//   npm run db:schema   -> crée les tables (table.sql) sur une base vide
//   npm run db:reset    -> supprime tout (reset.sql), recrée (table.sql) et remplit (seed.sql)
//
// Ajouter -- --yes pour ne pas avoir la question de confirmation (ex : npm run db:seed -- --yes)
// La connexion est lue dans .env : DATABASE_URL=postgresql://...

import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline/promises';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');

const commands = {
  schema: { files: ['table.sql'], destructive: false,
            description: 'créer les tables (table.sql)' },
  seed:   { files: ['seed.sql'], destructive: true,
            description: 'VIDER toutes les tables puis les remplir (seed.sql)' },
  reset:  { files: ['reset.sql', 'table.sql', 'seed.sql'], destructive: true,
            description: 'SUPPRIMER toutes les tables et leurs données, les recréer puis les remplir' },
};

const command = process.argv[2];
const skipConfirm = process.argv.includes('--yes');

if (!commands[command]) {
  console.error(`Commande inconnue : ${command ?? '(aucune)'}\nUtilisation : node scripts/db.mjs <${Object.keys(commands).join('|')}> [--yes]`);
  process.exit(1);
}

try { process.loadEnvFile(path.join(root, '.env')); } catch { /* pas de .env : on regarde l'environnement */ }

const url = process.env.DATABASE_URL;
if (!url) {
  console.error('DATABASE_URL manquant. Copie .env.example en .env et colle la chaîne de connexion Supabase.');
  process.exit(1);
}

// Affiche la cible sans le mot de passe
const target = new URL(url);
const targetLabel = `${target.hostname}:${target.port || 5432}${target.pathname}`;
const isLocal = ['localhost', '127.0.0.1', '::1'].includes(target.hostname);

const { files, destructive, description } = commands[command];
console.log(`Base cible : ${targetLabel}`);
console.log(`Action     : ${description}`);

if (destructive && !skipConfirm) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const answer = await rl.question('Toutes les données de ces tables seront perdues. Continuer ? (oui/non) ');
  rl.close();
  if (!['oui', 'o', 'yes', 'y'].includes(answer.trim().toLowerCase())) {
    console.log('Annulé.');
    process.exit(0);
  }
}

const client = new pg.Client({
  connectionString: url,
  ssl: isLocal ? false : { rejectUnauthorized: false },  // Supabase impose SSL
});

try {
  await client.connect();
  for (const file of files) {
    const sql = fs.readFileSync(path.join(root, file), 'utf8');
    const start = Date.now();
    process.stdout.write(`-> ${file} ... `);
    const result = await client.query(sql);
    console.log(`OK (${((Date.now() - start) / 1000).toFixed(1)} s)`);

    // seed.sql se termine par un récapitulatif du nombre de lignes par table
    const last = Array.isArray(result) ? result.at(-1) : result;
    if (file === 'seed.sql' && last?.rows?.length) console.table(last.rows);
  }
  console.log('Terminé.');
} catch (e) {
  console.log('ERREUR');
  console.error(`\n${e.message}`);
  if (e.detail) console.error(`Détail : ${e.detail}`);
  if (e.where)  console.error(`Où     : ${e.where}`);
  if (e.message.includes('already exists'))
    console.error('\nLes tables existent déjà : utilise "npm run db:reset" pour repartir de zéro.');
  console.error('\nRien n\'a été modifié par ce fichier (il est exécuté dans une transaction).');
  process.exitCode = 1;
} finally {
  await client.end().catch(() => {});
}
