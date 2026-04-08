// export libraries

// to create server eaisly
const express = require('express');
// to deal with PostgreSQL and manage connections for DB 
const { Pool } = require('pg');
// deal with path of files
const path = require('path');
// server
const app = express();

// Connection parameters for your PostgreSQL database
// it use env vars and if not exist it will use default values 
// it take vars from envs like as docker or k8s 
const pool = new Pool({
  user: process.env.DB_USER || 'postgres',
  host: process.env.DB_HOST || 'postgres-service',
  database: process.env.DB_DATABASE || 'postgres_db',
  password: process.env.DB_PASSWORD || 'mypassword',
  port: process.env.DB_PORT || 5432,
});

// view engine , show html dynamically 
// view : place for files of ejs html
// page to show data of db which is taken from app.js

app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

app.get('/', async (req, res) => {
  try {
    const client = await pool.connect(); // use parameters of var pool and connect 
    const result = await client.query('SELECT * FROM posts'); // select data from table and show it 
    const results = { 'results': (result) ? result.rows : null}; // put data in results
    res.render('pages/index', results); // render data which is show data of results of table
    client.release();
  }catch (err) {
    console.error(err);
    res.send("Error " + err);
  }
})

app.listen(8000, () => {
  console.log('Server is running at port 8000');
});

// in index.ejs it will replace some lines with data of table  