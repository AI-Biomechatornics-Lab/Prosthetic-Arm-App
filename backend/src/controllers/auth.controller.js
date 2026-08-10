const usersService = require('../services/users.service');

async function register(req, res, next) {
  try {
    const { name, surname, gender, birthdate } = req.body;
    if (!name || !surname || !gender || !birthdate) {
      return res.status(400).json({ error: 'name, surname, gender and birthdate are required' });
    }
    if (!['M', 'F'].includes(gender)) {
      return res.status(400).json({ error: 'gender must be "M" or "F"' });
    }
    const user = await usersService.register({ name, surname, gender, birthdate });
    res.status(201).json({ user });
  } catch (err) {
    next(err);
  }
}

async function login(req, res, next) {
  try {
    const { id } = req.body;
    if (!id) return res.status(400).json({ error: 'id is required' });

    const user = await usersService.findById(id);
    if (!user) return res.status(404).json({ error: 'User not found' });

    res.json({ user });
  } catch (err) {
    next(err);
  }
}

module.exports = { register, login };
