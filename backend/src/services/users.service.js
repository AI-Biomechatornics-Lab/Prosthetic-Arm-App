const pool = require('../db/pool');

async function register({ name, surname, gender, birthdate }) {
  const { rows } = await pool.query(
    `INSERT INTO users (name, surname, gender, birthdate)
     VALUES ($1, $2, $3, $4) RETURNING id, name, surname, gender, birthdate, created_at`,
    [name, surname, gender, birthdate],
  );
  return rows[0];
}

async function findById(id) {
  const { rows } = await pool.query(
    `SELECT id, name, surname, gender, birthdate, created_at FROM users WHERE id = $1`,
    [id],
  );
  return rows[0] || null;
}

module.exports = { register, findById };
