const express = require('express');
const router = express.Router();

// In-memory store — fine for a demo workload; swap for a real DB in production.
let tasks = [
  { id: 1, title: 'Provision infrastructure with Terraform', done: false },
  { id: 2, title: 'Deploy application to EKS', done: false },
  { id: 3, title: 'Configure CI/CD pipeline', done: false },
  { id: 4, title: 'Set up monitoring and logging', done: false },
  { id: 5, title: 'Implement security best practices', done: false },
  { id: 6, title: 'Conduct load testing and performance tuning', done: false },
  { id: 7, title: 'Document architecture and processes', done: false },
  { id: 8, title: 'Train team on new systems and workflows', done: false },
  { id: 9, title: 'Plan for disaster recovery and backups', done: false },
  { id: 10, title: 'Review and optimize costs', done: false }
];
let nextId = 11;

router.get('/', (req, res) => {
  res.json(tasks);
});

router.post('/', (req, res) => {
  const { title } = req.body;
  if (!title || typeof title !== 'string') {
    return res.status(400).json({ error: 'title (string) is required' });
  }
  const task = { id: nextId++, title, done: false };
  tasks.push(task);
  res.status(201).json(task);
});

router.patch('/:id/done', (req, res) => {
  const task = tasks.find((t) => t.id === parseInt(req.params.id, 10));
  if (!task) return res.status(404).json({ error: 'Task not found' });
  task.done = true;
  res.json(task);
});

router.delete('/:id', (req, res) => {
  const exists = tasks.some((t) => t.id === parseInt(req.params.id, 10));
  if (!exists) return res.status(404).json({ error: 'Task not found' });
  tasks = tasks.filter((t) => t.id !== parseInt(req.params.id, 10));
  res.status(204).send();
});

module.exports = router;
