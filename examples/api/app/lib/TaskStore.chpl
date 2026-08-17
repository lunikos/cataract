module TaskStore {
  private use List;

  record Task {
    var id: int;
    var title: string;
    var done: bool = false;
  }

  /* A `sync bool` as a mutex: writeEF acquires, readFE releases. Blocking on it
     yields the task, which blocking in a foreign call would not. */
  private var mutex: sync bool;
  private var items: list(Task) = seeded();
  private var nextId: int = 4;

  private proc seeded(): list(Task) {
    var l: list(Task);
    l.pushBack(new Task(1, "Read cataract_net.c", true));
    l.pushBack(new Task(2, "Write a route"));
    l.pushBack(new Task(3, "Benchmark the accept loop"));
    return l;
  }

  private proc lock() { mutex.writeEF(true); }
  private proc unlock() { mutex.readFE(); }

  /* A copy, so the lock is not held across serialisation. */
  proc snapshot(): list(Task) {
    lock();
    defer unlock();
    return items;
  }

  proc count(): int {
    lock();
    defer unlock();
    return items.size;
  }

  proc find(id: int, ref result: Task): bool {
    lock();
    defer unlock();
    for t in items {
      if t.id == id {
        result = t;
        return true;
      }
    }
    return false;
  }

  proc add(title: string): Task {
    lock();
    defer unlock();
    const created = new Task(nextId, title);
    nextId += 1;
    items.pushBack(created);
    return created;
  }

  proc setDone(id: int, done: bool, ref result: Task): bool {
    lock();
    defer unlock();
    for i in 0..<items.size {
      if items[i].id == id {
        items[i].done = done;
        result = items[i];
        return true;
      }
    }
    return false;
  }

  proc remove(id: int): bool {
    lock();
    defer unlock();
    for i in 0..<items.size {
      if items[i].id == id {
        items.getAndRemove(i);
        return true;
      }
    }
    return false;
  }
}
