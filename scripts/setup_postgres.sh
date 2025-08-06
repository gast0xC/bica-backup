#!/bin/bash
set -e

NETWORK_NAME="bica-net"
POSTGRES_CONTAINER_NAME="postgres-db"
POSTGRES_USER="myuser"
POSTGRES_PASSWORD="mypass"
POSTGRES_DB="mydatabase"

echo "Creating Docker network (if it doesn't exist)..."
docker network create $NETWORK_NAME || true

echo "Starting PostgreSQL container..."
docker run -d --name $POSTGRES_CONTAINER_NAME --network $NETWORK_NAME \
  -e POSTGRES_USER=$POSTGRES_USER \
  -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
  -e POSTGRES_DB=$POSTGRES_DB \
  postgres:15

echo "Waiting for PostgreSQL to become ready..."
for i in {1..30}; do
  if docker exec $POSTGRES_CONTAINER_NAME pg_isready -U $POSTGRES_USER > /dev/null 2>&1; then
    echo "PostgreSQL is ready!"
    break
  fi
  echo "Retrying ($i)..."
  sleep 2
done

echo "Populating the database with sample data..."
docker exec -i $POSTGRES_CONTAINER_NAME psql -U $POSTGRES_USER -d $POSTGRES_DB <<EOF
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  email TEXT NOT NULL UNIQUE,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS posts (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  title TEXT NOT NULL,
  content TEXT,
  published_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS comments (
  id SERIAL PRIMARY KEY,
  post_id INTEGER NOT NULL REFERENCES posts(id),
  author_name TEXT NOT NULL,
  comment TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO users (username, email) VALUES
  ('alice', 'alice@example.com'),
  ('bob', 'bob@example.com'),
  ('carol', 'carol@example.com')
ON CONFLICT DO NOTHING;

INSERT INTO posts (user_id, title, content, published_at) VALUES
  (1, 'First post', 'This is the content of the first post.', NOW() - INTERVAL '5 days'),
  (1, 'Second post', 'More content here.', NOW() - INTERVAL '2 days'),
  (2, 'Bob''s post', 'Bob writes something interesting.', NOW() - INTERVAL '3 days')
ON CONFLICT DO NOTHING;

INSERT INTO comments (post_id, author_name, comment) VALUES
  (1, 'Eve', 'Great post, thanks!'),
  (1, 'Mallory', 'I disagree with your point.'),
  (3, 'Trent', 'Nice one, Bob!')
ON CONFLICT DO NOTHING;
EOF

echo "PostgreSQL setup completed!"
