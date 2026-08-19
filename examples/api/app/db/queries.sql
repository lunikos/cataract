-- name: allTasks :many
SELECT * FROM tasks ORDER BY id;

-- name: tasksByState :many
SELECT * FROM tasks WHERE done = :done ORDER BY id;

-- name: taskById :one
SELECT * FROM tasks WHERE id = :id;

-- name: countTasks :one
SELECT COUNT(*) FROM tasks;

-- name: addTask :one
INSERT INTO tasks (title) VALUES (:title);

-- name: setTaskDone :one
UPDATE tasks SET done = :done WHERE id = :id;

-- name: deleteTask :one
DELETE FROM tasks WHERE id = :id;
