const { Pool } = require('pg');
const env = require('../config/env');

const pool = new Pool(env.db);

pool.on('error', (err) => {
  console.error('Unexpected PostgreSQL client error', err);
});

module.exports = pool;
