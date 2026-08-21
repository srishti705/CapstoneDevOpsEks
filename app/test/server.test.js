const request = require('supertest');
const app = require('../server');

describe('Health check', () => {
  it('GET /health returns 200 and status ok', async () => {
    const res = await request(app).get('/health');
    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe('ok');
  });
});

describe('Tasks API', () => {
  it('GET /api/tasks returns seeded tasks', async () => {
    const res = await request(app).get('/api/tasks');
    expect(res.statusCode).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body.length).toBeGreaterThanOrEqual(2);
  });

  it('POST /api/tasks creates a task', async () => {
    const res = await request(app).post('/api/tasks').send({ title: 'Write tests' });
    expect(res.statusCode).toBe(201);
    expect(res.body.title).toBe('Write tests');
    expect(res.body.done).toBe(false);
  });

  it('POST /api/tasks rejects missing title', async () => {
    const res = await request(app).post('/api/tasks').send({});
    expect(res.statusCode).toBe(400);
  });

  it('PATCH /api/tasks/:id/done marks a task done', async () => {
    const res = await request(app).patch('/api/tasks/1/done');
    expect(res.statusCode).toBe(200);
    expect(res.body.done).toBe(true);
  });

  it('PATCH on missing task returns 404', async () => {
    const res = await request(app).patch('/api/tasks/999/done');
    expect(res.statusCode).toBe(404);
  });
});
