const express = require('express');
const tasksRouter = require('./routes/tasks');

const app = express();
app.use(express.json());

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok', uptime: process.uptime() });
});

app.get('/', (req, res) => {
  res.json({
    message: 'DevOps Demo API',
    version: process.env.APP_VERSION || '1.0.0',
  });
});

app.use('/api/tasks', tasksRouter);

app.use((req, res) => res.status(404).json({ error: 'Not found' }));

const PORT = process.env.PORT || 3009;

if (require.main === module) {
  app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
}

module.exports = app;
