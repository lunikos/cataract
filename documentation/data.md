# Compile-time SQL

A project with `app/db/schema.sql` gets a generated module, `CataractSchema`,
holding one Chapel record per table and one procedure per named query. The SQL
is read by `cataract build`; the running server never parses a query string.

A misspelled column is a build error with a file and a line. A query taking a
`:limit` becomes a procedure taking `limit: int`, because that is what the
column says it is.

## The schema

```sql
-- app/db/schema.sql
-- record: Task
CREATE TABLE tasks (
  id INTEGER PRIMARY KEY,
  title TEXT NOT NULL,
  done BOOLEAN NOT NULL DEFAULT FALSE
);
```

becomes

```chapel
record Task {
  var id: int = 0;
  var title: string = "";
  var done: bool = false;
}

var tasks = new owned TasksTable(databaseDir);
```

| SQL type | Chapel type |
| --- | --- |
| `INTEGER`, `INT`, `BIGINT`, `SERIAL` | `int` |
| `REAL`, `FLOAT`, `DOUBLE`, `NUMERIC`, `DECIMAL` | `real` |
| `TEXT`, `VARCHAR(n)`, `CHAR(n)`, `BLOB` | `string` |
| `BOOLEAN`, `BOOL` | `bool` |

Anything else is a build error rather than a guess.

`DEFAULT` becomes the field's default value. `PRIMARY KEY` on an `INTEGER`
column makes it assigned on insert when it is left at zero, counting up from the
highest key already stored. `UNIQUE`, and a non-integer `PRIMARY KEY`, are
checked on insert and raise a `StoreError`.

The record is named after the table, singularised — `tasks` gives `Task`,
`entries` gives `Entry`. A `-- record: Name` comment on the line above the
statement overrides that.

## Named queries

```sql
-- app/db/queries.sql

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
```

Every statement needs a `-- name:` line above it. The name must be a Chapel
identifier; it is the name of the generated procedure.

The flag after the name picks the shape of that procedure:

| statement | flag | generated |
| --- | --- | --- |
| `SELECT` | `:many` (default) | `proc q(...): list(Row)` |
| `SELECT` | `:one` | `proc q(..., ref result: Row): bool` |
| `SELECT COUNT(*)` | | `proc q(...): int` |
| `INSERT` | `:exec` (default) | `proc q(...): int throws` — rows inserted |
| `INSERT` | `:one` | `proc q(...): Row throws` — the inserted row |
| `UPDATE` / `DELETE` | `:exec` (default) | `proc q(...): int` — rows affected |
| `UPDATE` / `DELETE` | `:one` | `proc q(...): bool`, `UPDATE :one` also takes `ref result` |

Using them:

```chapel
module ApiTasks {
  use Cataract;
  use CataractSchema;

  proc get(ctx: Context): Response {
    const rows = allTasks();
    var b = new JsonBuilder();
    b.beginObject();
    b.field("total", countTasks());
    b.key("tasks");
    b.beginArray();
    for t in rows {
      b.beginObject();
      b.field("id", t.id);
      b.field("title", t.title);
      b.field("done", t.done);
      b.endObject();
    }
    b.endArray();
    b.endObject();
    return jsonResponse(b.done());
  }

  proc post(ctx: Context): Response throws {
    const created = addTask(ctx.request.bodyText());
    return jsonResponse("{\"id\":" + created.id:string + "}", 201);
  }
}
```

```chapel
var task: Task;
if !taskById(id, task) then return problem(404, "no task with id " + id:string);

if !setTaskDone(true, id, task) then return problem(404, "gone");
```

Parameters appear in the generated signature in the order they first appear in
the statement, so `UPDATE ... SET done = :done WHERE id = :id` gives
`setTaskDone(done, id, ref result)`. Repeating a `:param` reuses the same
argument.

## The supported subset

```
SELECT * | col, col | COUNT(*)
  FROM table
  [WHERE condition]
  [ORDER BY col [ASC|DESC], ...]
  [LIMIT n | :param] [OFFSET n | :param]

INSERT INTO table (col, ...) VALUES (value, ...)

UPDATE table SET col = value | col + n | col - n, ... [WHERE condition]

DELETE FROM table [WHERE condition]
```

A condition is comparisons joined by `AND` and `OR`, without parentheses: `AND`
binds tighter, so `a = 1 AND b = 2 OR c = 3` is `(a AND b) OR c`. The
comparisons are `=`, `!=` (or `<>`), `<`, `<=`, `>`, `>=` and `LIKE`, where
`LIKE` takes `%` for any run of characters and `_` for one.

A projection generates its own record, named after the query:

```sql
-- name: taskTitles :many
SELECT id, title FROM tasks ORDER BY title;
```

```chapel
for row in taskTitles() do writeln(row.id, " ", row.title);   // TaskTitlesRow
```

Anything outside the subset — joins, subqueries, aggregates other than
`COUNT(*)`, `GROUP BY` — is rejected at build time. The generator says what it
does not understand instead of emitting code that half works.

## Seeds

`app/db/seed.sql` holds `INSERT` statements with literal values. They run at
start-up for any table that comes up empty, so a fresh checkout has data and an
existing database is left alone.

```sql
INSERT INTO tasks (title, done) VALUES ('Read cataract_net.c', TRUE);
INSERT INTO tasks (title) VALUES ('Write a route');
```

## Storage

Rows live in memory. Each table is a class holding a `list` of records and a
`sync bool` used as a mutex; every generated query takes that lock, so handlers
running on different tasks do not need their own.

```toml
[paths]
db = "app/db"          # where schema.sql, queries.sql and seed.sql live

[database]
path = "data"          # one file per table; unset means memory only
```

With `path` set, each table is mirrored to `<path>/<table>.rows`, one line per
row, tab-separated, with tabs and newlines inside a value escaped. The file is
loaded at start-up and rewritten whenever a query changes the table. Rewriting
the whole file keeps insert, update and delete on one code path and needs no
compaction; it also means writes cost the size of the table, which is the limit
worth knowing about.

Beyond the table lock and that file, this is not a database engine: there are no
transactions, no indexes and no query planner. It is a typed, durable collection
sized for the data a small service keeps beside itself. A project that outgrows
it should reach for a real database, and `CataractSchema` is deliberately a
generated module rather than a runtime dependency, so replacing it means
replacing one file.

`openDatabase()` is called by generated `main` before the server starts
listening.

## Errors

`insert` raises `StoreError` on a `UNIQUE` or primary-key collision, so the
generated `INSERT` procedures are `throws`:

```chapel
proc post(ctx: Context): Response throws {
  try {
    const created = addTask(title);
    return jsonResponse(payloadFor(created), 201);
  } catch e: StoreError {
    return problem(409, e.message());
  }
}
```

A handler declared `throws` that lets the error escape gets the framework's
default: logged, and answered `500`.

## A worked example

`examples/api` runs entirely on this. Its schema, queries and seed rows are
three short files, and the routes read as ordinary handlers calling ordinary
procedures.
