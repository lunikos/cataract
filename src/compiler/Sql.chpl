module Sql {
  private use List;
  private use Map;
  private use IO;
  private use FileSystem;
  private use Path;
  private use Diagnostics;
  private use Text only sub, chplLiteral;

  record Column {
    var name: string;
    var sqlType: string;
    var chapelType: string = "string";
    var primaryKey: bool = false;
    var unique: bool = false;
    var notNull: bool = false;
    var defaultLiteral: string = "";
  }

  record Table {
    var name: string;
    var recordName: string;
    var columns: list(Column);
    var primaryKey: string = "";
    var line: int = 0;

    proc has(column: string): bool throws {
      for c in columns do if c.name == column then return true;
      return false;
    }

    proc column(name: string): Column throws {
      for c in columns do if c.name == name then return c;
      return new Column();
    }
  }

  record Database {
    var present: bool = false;
    var schema: Schema;
    var queries: list(Query);
    var seeds: list(Query);

    proc tableCount(): int throws do return schema.order.size;
    proc queryCount(): int throws do return queries.size;
  }

  record Schema {
    var tables: map(string, Table);
    var order: list(string);

    proc size(): int throws do return order.size;
  }

  enum QueryKind { fetch, insert, update, erase }
  enum ResultShape { many, one, exec, count }

  record Condition {
    var column: string;
    var op: string;
    var operand: string;
    var chapelType: string = "string";
  }

  record Term {
    var conditions: list(Condition);
  }

  record Assignment {
    var column: string;
    var operand: string;
    var delta: string = "";
  }

  record Param {
    var name: string;
    var chapelType: string;
  }

  record Ordering {
    var column: string;
    var descending: bool = false;
  }

  record Query {
    var name: string;
    var kind: QueryKind = QueryKind.fetch;
    var shape: ResultShape = ResultShape.many;
    var table: string;
    var recordName: string;
    var projection: list(string);
    var wholeRow: bool = false;
    var counting: bool = false;
    var terms: list(Term);
    var assignments: list(Assignment);
    var insertColumns: list(string);
    var insertValues: list(string);
    var orderings: list(Ordering);
    var limitOperand: string = "";
    var offsetOperand: string = "";
    var params: list(Param);
    var line: int = 0;

    proc rowType(): string throws {
      return if wholeRow then recordName else pascal(name) + "Row";
    }
  }

  proc chapelTypeOf(sqlType: string): string throws {
    const t = sqlType.toUpper();
    if t.startsWith("INT") || t.startsWith("BIGINT") || t.startsWith("SERIAL") then
      return "int";
    if t.startsWith("REAL") || t.startsWith("FLOAT") || t.startsWith("DOUBLE") ||
       t.startsWith("NUMERIC") || t.startsWith("DECIMAL") then return "real";
    if t.startsWith("BOOL") then return "bool";
    if t.startsWith("TEXT") || t.startsWith("VARCHAR") || t.startsWith("CHAR") ||
       t.startsWith("BLOB") then return "string";
    return "";
  }

  proc pascal(name: string): string throws {
    var sb = "";
    var upper = true;
    for ch in name {
      const alpha = (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z");
      const digit = ch >= "0" && ch <= "9";
      if !alpha && !digit {
        upper = true;
        continue;
      }
      sb += if upper then ch.toUpper() else ch;
      upper = false;
    }
    return sb;
  }

  proc singular(name: string): string throws {
    if name.endsWith("ies") then return name[..<(name.size - 3)] + "y";
    if name.endsWith("ses") || name.endsWith("xes") || name.endsWith("zes") then
      return name[..<(name.size - 2)];
    if name.endsWith("ss") || name.endsWith("us") then return name;
    if name.endsWith("s") then return name[..<(name.size - 1)];
    return name;
  }

  record Statement {
    var text: string;
    var line: int;
    var directive: string;
  }

  proc splitStatements(source: string): list(Statement) throws {
    var statements: list(Statement);
    var buffer = "";
    var startLine = 1;
    var lineNo = 0;
    var lastComment = "";
    var directive = "";

    for raw in source.split("\n") {
      lineNo += 1;
      var line = raw;
      const marker = line.find("--");
      if marker != -1 {
        const comment = line[(marker + 2)..].strip();
        line = line[..<marker];
        if !comment.isEmpty() then lastComment = comment;
      }
      if line.strip().isEmpty() then continue;

      if buffer.strip().isEmpty() {
        startLine = lineNo;
        directive = lastComment;
      }
      buffer += " " + line;

      while buffer.find(";") != -1 {
        const stop = buffer.find(";");
        const statement = buffer[..<stop].strip();
        if !statement.isEmpty() then
          statements.pushBack(new Statement(statement, startLine, directive));
        buffer = buffer[(stop + 1)..];
        directive = "";
        lastComment = "";
        startLine = lineNo;
      }
    }

    if !buffer.strip().isEmpty() then
      statements.pushBack(new Statement(buffer.strip(), startLine, directive));
    return statements;
  }

  proc tokenize(statement: string): list(string) throws {
    var tokens: list(string);
    var i = 0;
    const n = statement.numBytes;

    while i < n {
      const c = statement.byte(i);
      if c == 32 || c == 9 || c == 13 || c == 10 {
        i += 1;
        continue;
      }
      if c == 39 {
        var j = i + 1;
        while j < n && statement.byte(j) != 39 do j += 1;
        tokens.pushBack("'" + sub(statement, i + 1, j));
        i = j + 1;
        continue;
      }
      const wordish = (c >= 97 && c <= 122) || (c >= 65 && c <= 90) ||
                      (c >= 48 && c <= 57) || c == 95 || c == 58 || c == 46;
      if wordish {
        var j = i;
        while j < n {
          const w = statement.byte(j);
          const ok = (w >= 97 && w <= 122) || (w >= 65 && w <= 90) ||
                     (w >= 48 && w <= 57) || w == 95 || w == 58 || w == 46;
          if !ok then break;
          j += 1;
        }
        tokens.pushBack(sub(statement, i, j));
        i = j;
        continue;
      }
      if (c == 60 || c == 62 || c == 33) && i + 1 < n && statement.byte(i + 1) == 61 {
        tokens.pushBack(sub(statement, i, i + 2));
        i += 2;
        continue;
      }
      if c == 60 && i + 1 < n && statement.byte(i + 1) == 62 {
        tokens.pushBack("!=");
        i += 2;
        continue;
      }
      tokens.pushBack(sub(statement, i, i + 1));
      i += 1;
    }
    return tokens;
  }

  proc parseSchema(path: string, ref diags: Bag): Schema throws {
    var schema = new Schema();
    const source = readFileText(path, diags);
    if source.isEmpty() then return schema;

    for statement in splitStatements(source) {
      var tokens = tokenize(statement.text);
      if tokens.size < 3 {
        diags.error(path, statement.line, "statement is not a CREATE TABLE");
        continue;
      }
      if tokens[0].toUpper() != "CREATE" || tokens[1].toUpper() != "TABLE" {
        diags.error(path, statement.line,
                    "only CREATE TABLE belongs in a schema file",
                    "named queries go in queries.sql");
        continue;
      }

      var at = 2;
      if at + 2 < tokens.size && tokens[at].toUpper() == "IF" &&
         tokens[at + 1].toUpper() == "NOT" && tokens[at + 2].toUpper() == "EXISTS" then
        at += 3;

      if at >= tokens.size {
        diags.error(path, statement.line, "CREATE TABLE has no table name");
        continue;
      }

      var table = new Table();
      table.name = tokens[at];
      table.line = statement.line;
      table.recordName = recordNameFor(table.name, statement.directive);
      at += 1;

      if at >= tokens.size || tokens[at] != "(" {
        diags.error(path, statement.line,
                    "expected a column list after \"" + table.name + "\"");
        continue;
      }
      at += 1;

      var group: list(string);
      var depth = 1;
      while at < tokens.size {
        const token = tokens[at];
        if token == "(" then depth += 1;
        if token == ")" {
          depth -= 1;
          if depth == 0 {
            at += 1;
            break;
          }
        }
        if token == "," && depth == 1 {
          readColumn(group, table, path, statement.line, diags);
          group.clear();
          at += 1;
          continue;
        }
        group.pushBack(token);
        at += 1;
      }
      readColumn(group, table, path, statement.line, diags);

      if table.columns.isEmpty() {
        diags.error(path, statement.line, "table \"" + table.name + "\" has no columns");
        continue;
      }
      if schema.tables.contains(table.name) {
        diags.error(path, statement.line, "table \"" + table.name + "\" is declared twice");
        continue;
      }

      schema.tables[table.name] = table;
      schema.order.pushBack(table.name);
    }

    return schema;
  }

  private proc recordNameFor(table: string, directive: string): string throws {
    if directive.toLower().startsWith("record:") {
      const declared = directive[7..].strip();
      if !declared.isEmpty() then return declared;
    }
    return pascal(singular(table));
  }

  private proc readColumn(const ref group: list(string), ref table: Table,
                          path: string, line: int, ref diags: Bag) throws {
    if group.isEmpty() then return;

    const head = group[0].toUpper();
    if head == "PRIMARY" {
      for token in group do
        if table.has(token) then table.primaryKey = token;
      markPrimaryKey(table);
      return;
    }
    if head == "UNIQUE" || head == "CHECK" || head == "FOREIGN" || head == "CONSTRAINT" {
      diags.warn(path, line, "table constraint \"" + group[0] + "\" is not enforced");
      return;
    }

    if group.size < 2 {
      diags.error(path, line, "column \"" + group[0] + "\" has no type");
      return;
    }

    var column = new Column();
    column.name = group[0];
    column.sqlType = group[1].toUpper();
    column.chapelType = chapelTypeOf(column.sqlType);
    if column.chapelType.isEmpty() {
      diags.error(path, line, "unsupported column type \"" + group[1] + "\"",
                  "use INTEGER, REAL, TEXT or BOOLEAN");
      return;
    }

    var at = 2;
    while at < group.size {
      const word = group[at].toUpper();
      select word {
        when "PRIMARY" {
          column.primaryKey = true;
          table.primaryKey = column.name;
        }
        when "UNIQUE" do column.unique = true;
        when "NOT" do column.notNull = true;
        when "DEFAULT" {
          if at + 1 < group.size {
            column.defaultLiteral = literalOf(group[at + 1], column.chapelType);
            at += 1;
          }
        }
        otherwise do ;
      }
      at += 1;
    }

    if table.has(column.name) then
      diags.error(path, line, "column \"" + column.name + "\" is declared twice");
    else
      table.columns.pushBack(column);
  }

  private proc markPrimaryKey(ref table: Table) throws {
    for i in 0..<table.columns.size do
      if table.columns[i].name == table.primaryKey then table.columns[i].primaryKey = true;
  }

  proc literalOf(token: string, chapelType: string): string throws {
    if token.startsWith("'") then return chplLiteral(token[1..]);
    const upper = token.toUpper();
    select chapelType {
      when "bool" do
        return if upper == "TRUE" || token == "1" then "true" else "false";
      when "string" do return chplLiteral(token);
      otherwise do return token;
    }
  }

  proc readFileText(path: string, ref diags: Bag): string throws {
    try {
      var reader = openReader(path);
      defer try! reader.close();
      return reader.readAll(string);
    } catch e {
      diags.error(path, 0, "cannot read " + path + ": " + e.message());
      return "";
    }
  }

  proc parseQueries(path: string, const ref schema: Schema,
                    ref diags: Bag): list(Query) throws {
    var queries: list(Query);
    const source = readFileText(path, diags);
    if source.isEmpty() then return queries;

    for statement in splitStatements(source) {
      var query = new Query();
      query.line = statement.line;

      if !statement.directive.toLower().startsWith("name:") {
        diags.error(path, statement.line, "query has no name",
                    "put `-- name: myQuery :one` above the statement");
        continue;
      }

      var header = statement.directive[5..].strip().split(" ");
      query.name = header[0].strip();
      query.shape = ResultShape.many;
      for i in 1..<header.size {
        const flag = header[i].strip().toLower();
        select flag {
          when ":one" do query.shape = ResultShape.one;
          when ":many" do query.shape = ResultShape.many;
          when ":exec" do query.shape = ResultShape.exec;
          when "" do ;
          otherwise do diags.error(path, statement.line,
                                   "unknown query flag \"" + flag + "\"",
                                   "use :one, :many or :exec");
        }
      }

      if query.name.isEmpty() || !isChapelIdentifier(query.name) {
        diags.error(path, statement.line,
                    "\"" + query.name + "\" is not a usable query name",
                    "query names must be Chapel identifiers");
        continue;
      }

      var tokens = tokenize(statement.text);
      if tokens.isEmpty() then continue;

      select tokens[0].toUpper() {
        when "SELECT" do parseSelect(tokens, query, schema, path, diags);
        when "INSERT" do parseInsert(tokens, query, schema, path, diags);
        when "UPDATE" do parseUpdate(tokens, query, schema, path, diags);
        when "DELETE" do parseDelete(tokens, query, schema, path, diags);
        otherwise do diags.error(path, statement.line,
                                 "unsupported statement \"" + tokens[0] + "\"",
                                 "use SELECT, INSERT, UPDATE or DELETE");
      }

      if query.table.isEmpty() then continue;
      queries.pushBack(query);
    }

    return queries;
  }

  proc parseSeeds(path: string, const ref schema: Schema,
                  ref diags: Bag): list(Query) throws {
    var seeds: list(Query);
    const source = readFileText(path, diags);
    if source.isEmpty() then return seeds;

    var counter = 0;
    for statement in splitStatements(source) {
      var tokens = tokenize(statement.text);
      if tokens.isEmpty() then continue;
      if tokens[0].toUpper() != "INSERT" {
        diags.error(path, statement.line, "a seed file holds INSERT statements only");
        continue;
      }

      counter += 1;
      var query = new Query();
      query.line = statement.line;
      query.name = "seed" + counter:string;
      parseInsert(tokens, query, schema, path, diags);
      if query.table.isEmpty() then continue;
      if !query.params.isEmpty() {
        diags.error(path, statement.line, "a seed row cannot take parameters",
                    "write the value instead of :" + query.params[0].name);
        continue;
      }
      seeds.pushBack(query);
    }
    return seeds;
  }

  proc isChapelIdentifier(name: string): bool throws {
    if name.isEmpty() then return false;
    var first = true;
    for ch in name {
      const alpha = (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z") || ch == "_";
      const digit = ch >= "0" && ch <= "9";
      if first && !alpha then return false;
      if !alpha && !digit then return false;
      first = false;
    }
    return true;
  }

  private proc resolveTable(name: string, ref query: Query, const ref schema: Schema,
                            path: string, ref diags: Bag): bool throws {
    if !schema.tables.contains(name) {
      diags.error(path, query.line, "unknown table \"" + name + "\"",
                  "add it to the schema file, or check the spelling");
      return false;
    }
    query.table = name;
    query.recordName = schema.tables[name].recordName;
    return true;
  }

  private proc keywordAt(const ref tokens: list(string), at: int, word: string): bool throws {
    return at < tokens.size && tokens[at].toUpper() == word;
  }

  private proc parseSelect(const ref tokens: list(string), ref query: Query,
                           const ref schema: Schema, path: string,
                           ref diags: Bag) throws {
    query.kind = QueryKind.fetch;

    var at = 1;
    var projection: list(string);
    while at < tokens.size && tokens[at].toUpper() != "FROM" {
      const token = tokens[at];
      if token == "," || token == "(" || token == ")" {
        at += 1;
        continue;
      }
      if token == "*" && projection.isEmpty() then query.wholeRow = true;
      else if token.toUpper() == "COUNT" then query.counting = true;
      else if token != "*" then projection.pushBack(token);
      at += 1;
    }

    if !keywordAt(tokens, at, "FROM") {
      diags.error(path, query.line, "SELECT has no FROM clause");
      return;
    }
    at += 1;
    if at >= tokens.size {
      diags.error(path, query.line, "FROM has no table name");
      return;
    }
    if !resolveTable(tokens[at], query, schema, path, diags) then return;
    at += 1;

    const table = schema.tables[query.table];
    if query.counting {
      query.shape = ResultShape.one;
      projection.clear();
    } else if !query.wholeRow {
      for column in projection do
        if !table.has(column) then
          diags.error(path, query.line,
                      "table \"" + query.table + "\" has no column \"" + column + "\"");
      query.projection = projection;
      if projection.isEmpty() then query.wholeRow = true;
    }

    parseTail(tokens, at, query, schema, path, diags);
  }

  proc parseInsert(const ref tokens: list(string), ref query: Query,
                           const ref schema: Schema, path: string,
                           ref diags: Bag) throws {
    query.kind = QueryKind.insert;
    if query.shape == ResultShape.many then query.shape = ResultShape.exec;

    var at = 1;
    if keywordAt(tokens, at, "INTO") then at += 1;
    if at >= tokens.size {
      diags.error(path, query.line, "INSERT has no table name");
      return;
    }
    if !resolveTable(tokens[at], query, schema, path, diags) then return;
    at += 1;

    const table = schema.tables[query.table];

    if !keywordAt(tokens, at, "(") && (at >= tokens.size || tokens[at] != "(") {
      diags.error(path, query.line, "INSERT needs an explicit column list");
      return;
    }
    at += 1;
    while at < tokens.size && tokens[at] != ")" {
      if tokens[at] != "," {
        if !table.has(tokens[at]) then
          diags.error(path, query.line,
                      "table \"" + query.table + "\" has no column \"" + tokens[at] + "\"");
        else query.insertColumns.pushBack(tokens[at]);
      }
      at += 1;
    }
    at += 1;

    if !keywordAt(tokens, at, "VALUES") {
      diags.error(path, query.line, "INSERT has no VALUES clause");
      return;
    }
    at += 1;
    if at < tokens.size && tokens[at] == "(" then at += 1;

    var slot = 0;
    while at < tokens.size && tokens[at] != ")" {
      if tokens[at] != "," {
        if slot >= query.insertColumns.size {
          diags.error(path, query.line, "INSERT has more values than columns");
          return;
        }
        const column = table.column(query.insertColumns[slot]);
        query.insertValues.pushBack(operandOf(tokens[at], column.chapelType, query,
                                              path, diags));
        slot += 1;
      }
      at += 1;
    }

    if slot != query.insertColumns.size then
      diags.error(path, query.line, "INSERT has fewer values than columns");
  }

  private proc parseUpdate(const ref tokens: list(string), ref query: Query,
                           const ref schema: Schema, path: string,
                           ref diags: Bag) throws {
    query.kind = QueryKind.update;
    if query.shape == ResultShape.many then query.shape = ResultShape.exec;

    var at = 1;
    if at >= tokens.size {
      diags.error(path, query.line, "UPDATE has no table name");
      return;
    }
    if !resolveTable(tokens[at], query, schema, path, diags) then return;
    at += 1;

    if !keywordAt(tokens, at, "SET") {
      diags.error(path, query.line, "UPDATE has no SET clause");
      return;
    }
    at += 1;

    const table = schema.tables[query.table];

    while at < tokens.size {
      const upper = tokens[at].toUpper();
      if upper == "WHERE" then break;
      if tokens[at] == "," {
        at += 1;
        continue;
      }

      const columnName = tokens[at];
      if !table.has(columnName) {
        diags.error(path, query.line,
                    "table \"" + query.table + "\" has no column \"" + columnName + "\"");
        return;
      }
      const column = table.column(columnName);
      at += 1;
      if at >= tokens.size || tokens[at] != "=" {
        diags.error(path, query.line, "expected = after " + columnName);
        return;
      }
      at += 1;
      if at >= tokens.size {
        diags.error(path, query.line, "SET " + columnName + " has no value");
        return;
      }

      var assignment = new Assignment();
      assignment.column = columnName;

      if tokens[at] == columnName && at + 2 < tokens.size &&
         (tokens[at + 1] == "+" || tokens[at + 1] == "-") {
        assignment.operand = "row." + columnName;
        assignment.delta = tokens[at + 1] +
                           operandOf(tokens[at + 2], column.chapelType, query, path, diags);
        at += 3;
      } else {
        assignment.operand = operandOf(tokens[at], column.chapelType, query, path, diags);
        at += 1;
      }
      query.assignments.pushBack(assignment);
    }

    if query.assignments.isEmpty() then
      diags.error(path, query.line, "UPDATE assigns nothing");

    parseTail(tokens, at, query, schema, path, diags);
  }

  private proc parseDelete(const ref tokens: list(string), ref query: Query,
                           const ref schema: Schema, path: string,
                           ref diags: Bag) throws {
    query.kind = QueryKind.erase;
    if query.shape == ResultShape.many then query.shape = ResultShape.exec;

    var at = 1;
    if keywordAt(tokens, at, "FROM") then at += 1;
    if at >= tokens.size {
      diags.error(path, query.line, "DELETE has no table name");
      return;
    }
    if !resolveTable(tokens[at], query, schema, path, diags) then return;
    at += 1;

    parseTail(tokens, at, query, schema, path, diags);
  }

  private proc parseTail(const ref tokens: list(string), in at: int, ref query: Query,
                         const ref schema: Schema, path: string, ref diags: Bag) throws {
    const table = schema.tables[query.table];

    if keywordAt(tokens, at, "WHERE") {
      at += 1;
      var term = new Term();
      while at < tokens.size {
        const upper = tokens[at].toUpper();
        if upper == "ORDER" || upper == "LIMIT" || upper == "OFFSET" then break;
        if upper == "AND" {
          at += 1;
          continue;
        }
        if upper == "OR" {
          query.terms.pushBack(term);
          term = new Term();
          at += 1;
          continue;
        }

        const columnName = tokens[at];
        if !table.has(columnName) {
          diags.error(path, query.line,
                      "table \"" + query.table + "\" has no column \"" + columnName + "\"");
          return;
        }
        const column = table.column(columnName);
        at += 1;
        if at >= tokens.size {
          diags.error(path, query.line, "WHERE " + columnName + " has no comparison");
          return;
        }

        var condition = new Condition();
        condition.column = columnName;
        condition.chapelType = column.chapelType;
        condition.op = tokens[at].toUpper();
        at += 1;
        if at >= tokens.size {
          diags.error(path, query.line, "WHERE " + columnName + " has no value");
          return;
        }

        if condition.op == "LIKE" {
          condition.operand = operandOf(tokens[at], "string", query, path, diags);
        } else if condition.op == "=" || condition.op == "!=" || condition.op == "<" ||
                  condition.op == "<=" || condition.op == ">" || condition.op == ">=" {
          condition.operand = operandOf(tokens[at], column.chapelType, query, path, diags);
        } else {
          diags.error(path, query.line,
                      "unsupported comparison \"" + condition.op + "\"",
                      "use =, !=, <, <=, >, >= or LIKE");
          return;
        }
        at += 1;
        term.conditions.pushBack(condition);
      }
      if !term.conditions.isEmpty() then query.terms.pushBack(term);
    }

    if keywordAt(tokens, at, "ORDER") {
      at += 1;
      if keywordAt(tokens, at, "BY") then at += 1;
      while at < tokens.size {
        const upper = tokens[at].toUpper();
        if upper == "LIMIT" || upper == "OFFSET" then break;
        if tokens[at] == "," {
          at += 1;
          continue;
        }
        if upper == "ASC" || upper == "DESC" {
          if !query.orderings.isEmpty() then
            query.orderings[query.orderings.size - 1].descending = (upper == "DESC");
          at += 1;
          continue;
        }
        if !table.has(tokens[at]) {
          diags.error(path, query.line,
                      "table \"" + query.table + "\" has no column \"" + tokens[at] + "\"");
          return;
        }
        query.orderings.pushBack(new Ordering(tokens[at], false));
        at += 1;
      }
    }

    if keywordAt(tokens, at, "LIMIT") {
      at += 1;
      if at < tokens.size {
        query.limitOperand = operandOf(tokens[at], "int", query, path, diags);
        at += 1;
      }
    }

    if keywordAt(tokens, at, "OFFSET") {
      at += 1;
      if at < tokens.size {
        query.offsetOperand = operandOf(tokens[at], "int", query, path, diags);
        at += 1;
      }
    }
  }

  private proc operandOf(token: string, chapelType: string, ref query: Query,
                         path: string, ref diags: Bag): string throws {
    if token.startsWith(":") {
      const name = token[1..];
      if !isChapelIdentifier(name) {
        diags.error(path, query.line, "\":" + name + "\" is not a usable parameter name");
        return "";
      }
      for existing in query.params do
        if existing.name == name then return name;
      query.params.pushBack(new Param(name, chapelType));
      return name;
    }
    return literalOf(token, chapelType);
  }

  private proc hasSeedFor(const ref seeds: list(Query), table: string): bool throws {
    for seed in seeds do if seed.table == table then return true;
    return false;
  }

  proc emitSchema(const ref schema: Schema, const ref queries: list(Query),
                  const ref seeds: list(Query), databaseDir: string,
                  banner: string): string throws {
    var sb = banner;
    sb += "module CataractSchema {\n";
    sb += "  public use Store;\n";
    sb += "  private use List;\n";
    sb += "  private use Sort;\n\n";
    sb += "  config const databaseDir = " + chplLiteral(databaseDir) + ";\n\n";

    for name in schema.order {
      const table = schema.tables[name];
      sb += recordFor(table);
      sb += codecFor(table);
      sb += tableClassFor(table);
    }

    for name in schema.order {
      const table = schema.tables[name];
      sb += "  var " + table.name + " = new owned " + pascal(table.name) +
             "Table(databaseDir);\n";
    }
    sb += "\n";

    sb += "  proc openDatabase() {\n";
    for name in schema.order {
      sb += "    " + name + ".load();\n";
      if hasSeedFor(seeds, name) then
        sb += "    if " + name + ".count() == 0 then try! seed" + pascal(name) + "();\n";
    }
    sb += "  }\n\n";

    for name in schema.order {
      if !hasSeedFor(seeds, name) then continue;
      sb += "  proc seed" + pascal(name) + "() throws {\n";
      for seed in seeds {
        if seed.table != name then continue;
        sb += "    {\n";
        sb += "      var row = new " + schema.tables[name].recordName + "();\n";
        for i in 0..<seed.insertColumns.size do
          sb += "      row." + seed.insertColumns[i] + " = " + seed.insertValues[i] + ";\n";
        sb += "      " + name + ".insert(row);\n";
        sb += "    }\n";
      }
      sb += "  }\n\n";
    }

    for query in queries do sb += queryProc(query, schema);

    sb += "}\n";
    return sb;
  }

  private proc recordFor(const ref table: Table): string throws {
    var sb = "  record " + table.recordName + " {\n";
    for column in table.columns {
      sb += "    var " + column.name + ": " + column.chapelType + " = ";
      if !column.defaultLiteral.isEmpty() then sb += column.defaultLiteral;
      else sb += emptyValue(column.chapelType);
      sb += ";\n";
    }
    sb += "  }\n\n";
    return sb;
  }

  private proc emptyValue(chapelType: string): string throws {
    select chapelType {
      when "int" do return "0";
      when "real" do return "0.0";
      when "bool" do return "false";
      otherwise do return "\"\"";
    }
  }

  private proc cellExpression(column: Column): string throws {
    select column.chapelType {
      when "string" do return "encodeCell(row." + column.name + ")";
      when "bool" do
        return "(if row." + column.name + " then \"true\" else \"false\")";
      otherwise do return "row." + column.name + ":string";
    }
  }

  private proc cellDecoder(column: Column, position: int): string throws {
    const cell = "cells[" + position:string + "]";
    select column.chapelType {
      when "string" do return cell;
      when "int" do return "toInt(" + cell + ")";
      when "real" do return "toReal(" + cell + ")";
      otherwise do return "toBool(" + cell + ")";
    }
  }

  private proc codecFor(const ref table: Table): string throws {
    var sb = "  proc encode" + table.recordName + "(const ref row: " +
              table.recordName + "): string {\n";
    sb += "    var cells = \"\";\n";
    var first = true;
    for column in table.columns {
      if !first then sb += "    cells += \"\\t\";\n";
      sb += "    cells += " + cellExpression(column) + ";\n";
      first = false;
    }
    sb += "    return cells;\n";
    sb += "  }\n\n";

    sb += "  proc decode" + table.recordName + "(line: string, ref row: " +
           table.recordName + "): bool {\n";
    sb += "    const cells = cellsOf(line);\n";
    sb += "    if cells.size < " + table.columns.size:string + " then return false;\n";
    var at = 0;
    for column in table.columns {
      sb += "    row." + column.name + " = " + cellDecoder(column, at) + ";\n";
      at += 1;
    }
    sb += "    return true;\n";
    sb += "  }\n\n";
    return sb;
  }

  private proc tableClassFor(const ref table: Table): string throws {
    const className = pascal(table.name) + "Table";
    const hasKey = !table.primaryKey.isEmpty();
    const keyColumn = table.column(table.primaryKey);
    const autoKey = hasKey && keyColumn.chapelType == "int";

    var sb = "  class " + className + " {\n";
    sb += "    var rows: list(" + table.recordName + ");\n";
    sb += "    var gate: sync bool;\n";
    sb += "    var nextKey: int = 1;\n";
    sb += "    var journal: owned Journal;\n\n";

    sb += "    proc init(directory: string) {\n";
    sb += "      this.journal = new Journal(directory, " + chplLiteral(table.name) + ");\n";
    sb += "      init this;\n";
    sb += "      gate.writeEF(true);\n";
    sb += "    }\n\n";

    sb += "    proc lock() do gate.readFE();\n";
    sb += "    proc unlock() do gate.writeEF(true);\n\n";

    sb += "    proc load() {\n";
    sb += "      lock();\n";
    sb += "      defer unlock();\n";
    sb += "      journal.prepare();\n";
    sb += "      rows.clear();\n";
    sb += "      for line in journal.storedLines() {\n";
    sb += "        var row = new " + table.recordName + "();\n";
    sb += "        if !decode" + table.recordName + "(line, row) then continue;\n";
    sb += "        rows.pushBack(row);\n";
    if autoKey then
      sb += "        if row." + table.primaryKey + " >= nextKey then nextKey = row." +
             table.primaryKey + " + 1;\n";
    sb += "      }\n";
    sb += "    }\n\n";

    sb += "    proc save() {\n";
    sb += "      if !journal.ready() then return;\n";
    sb += "      var lines: list(string);\n";
    sb += "      for row in rows do lines.pushBack(encode" + table.recordName + "(row));\n";
    sb += "      journal.persist(lines);\n";
    sb += "    }\n\n";

    sb += "    proc all(): list(" + table.recordName + ") {\n";
    sb += "      lock();\n";
    sb += "      defer unlock();\n";
    sb += "      return rows;\n";
    sb += "    }\n\n";

    sb += "    proc count(): int {\n";
    sb += "      lock();\n";
    sb += "      defer unlock();\n";
    sb += "      return rows.size;\n";
    sb += "    }\n\n";

    sb += "    proc truncate(): int {\n";
    sb += "      lock();\n";
    sb += "      defer unlock();\n";
    sb += "      const removed = rows.size;\n";
    sb += "      rows.clear();\n";
    if autoKey then sb += "      nextKey = 1;\n";
    sb += "      save();\n";
    sb += "      return removed;\n";
    sb += "    }\n\n";

    sb += "    proc insertLocked(in row: " + table.recordName + "): " +
           table.recordName + " throws {\n";
    if autoKey {
      sb += "      if row." + table.primaryKey + " == 0 {\n";
      sb += "        row." + table.primaryKey + " = nextKey;\n";
      sb += "        nextKey += 1;\n";
      sb += "      } else if row." + table.primaryKey + " >= nextKey {\n";
      sb += "        nextKey = row." + table.primaryKey + " + 1;\n";
      sb += "      }\n";
    }
    for column in table.columns {
      if !column.unique && !(column.primaryKey && !autoKey) then continue;
      sb += "      for existing in rows do\n";
      sb += "        if existing." + column.name + " == row." + column.name + " then\n";
      sb += "          conflict(" + chplLiteral(table.name) + ", " +
             chplLiteral(column.name) + ", " + stringOf(column) + ");\n";
    }
    sb += "      rows.pushBack(row);\n";
    sb += "      save();\n";
    sb += "      return row;\n";
    sb += "    }\n\n";

    sb += "    proc insert(in row: " + table.recordName + "): " + table.recordName +
           " throws {\n";
    sb += "      lock();\n";
    sb += "      defer unlock();\n";
    sb += "      return insertLocked(row);\n";
    sb += "    }\n";
    sb += "  }\n\n";
    return sb;
  }

  private proc stringOf(column: Column): string throws {
    return if column.chapelType == "string" then "row." + column.name
           else "row." + column.name + ":string";
  }

  private proc conditionExpression(const ref query: Query, rowName: string): string throws {
    if query.terms.isEmpty() then return "true";

    var clauses: list(string);
    for term in query.terms {
      var parts: list(string);
      for condition in term.conditions {
        const field = rowName + "." + condition.column;
        if condition.op == "LIKE" then
          parts.pushBack("likeMatch(" + field + ", " + condition.operand + ")");
        else
          parts.pushBack(field + " " +
                         (if condition.op == "=" then "==" else condition.op) + " " +
                         condition.operand);
      }
      var joined = "";
      for part in parts {
        if !joined.isEmpty() then joined += " && ";
        joined += part;
      }
      clauses.pushBack(if parts.size > 1 then "(" + joined + ")" else joined);
    }

    var sb = "";
    for clause in clauses {
      if !sb.isEmpty() then sb += " || ";
      sb += clause;
    }
    return sb;
  }

  private proc signature(const ref query: Query): string throws {
    var sb = "";
    for item in query.params {
      if !sb.isEmpty() then sb += ", ";
      sb += item.name + ": " + item.chapelType;
    }
    return sb;
  }

  private proc comparatorName(const ref query: Query): string throws {
    return "Order" + pascal(query.name);
  }

  private proc comparatorFor(const ref query: Query, const ref schema: Schema): string throws {
    if query.orderings.isEmpty() then return "";
    const table = schema.tables[query.table];

    var sb = "  record " + comparatorName(query) + ": relativeComparator {\n";
    sb += "    proc compare(const ref a: " + table.recordName + ", const ref b: " +
           table.recordName + "): int {\n";
    for ordering in query.orderings {
      const column = table.column(ordering.column);
      const left = if column.chapelType == "bool" then "a." + ordering.column + ": int"
                   else "a." + ordering.column;
      const right = if column.chapelType == "bool" then "b." + ordering.column + ": int"
                    else "b." + ordering.column;
      sb += "      if " + left + " != " + right + " then\n";
      sb += "        return if " + left + " " +
             (if ordering.descending then ">" else "<") + " " + right +
             " then -1 else 1;\n";
    }
    sb += "      return 0;\n";
    sb += "    }\n";
    sb += "  }\n\n";
    return sb;
  }

  private proc projectionRecord(const ref query: Query,
                                const ref schema: Schema): string throws {
    if query.wholeRow || query.counting then return "";
    const table = schema.tables[query.table];

    var sb = "  record " + query.rowType() + " {\n";
    for name in query.projection {
      const column = table.column(name);
      sb += "    var " + name + ": " + column.chapelType + " = " +
             emptyValue(column.chapelType) + ";\n";
    }
    sb += "  }\n\n";
    return sb;
  }

  private proc projectExpression(const ref query: Query, rowName: string): string throws {
    if query.wholeRow then return rowName;
    var sb = "new " + query.rowType() + "(";
    var first = true;
    for name in query.projection {
      if !first then sb += ", ";
      sb += rowName + "." + name;
      first = false;
    }
    return sb + ")";
  }

  private proc queryProc(const ref query: Query, const ref schema: Schema): string throws {
    select query.kind {
      when QueryKind.fetch do return selectProc(query, schema);
      when QueryKind.insert do return insertProc(query, schema);
      when QueryKind.update do return updateProc(query, schema);
      otherwise do return deleteProc(query, schema);
    }
  }

  private proc selectProc(const ref query: Query, const ref schema: Schema): string throws {
    const table = schema.tables[query.table];
    var sb = projectionRecord(query, schema);
    sb += comparatorFor(query, schema);

    const condition = conditionExpression(query, "row");
    const bounded = !query.limitOperand.isEmpty() || !query.offsetOperand.isEmpty();

    if query.counting {
      sb += "  proc " + query.name + "(" + signature(query) + "): int {\n";
      sb += "    " + query.table + ".lock();\n";
      sb += "    defer " + query.table + ".unlock();\n";
      sb += "    var matched = 0;\n";
      sb += "    for row in " + query.table + ".rows do\n";
      sb += "      if " + condition + " then matched += 1;\n";
      sb += "    return matched;\n";
      sb += "  }\n\n";
      return sb;
    }

    const returnsOne = query.shape == ResultShape.one;
    if returnsOne then
      sb += "  proc " + query.name + "(" + signature(query) +
             (if query.params.isEmpty() then "" else ", ") + "ref result: " +
             query.rowType() + "): bool {\n";
    else
      sb += "  proc " + query.name + "(" + signature(query) + "): list(" +
             query.rowType() + ") {\n";

    sb += "    " + query.table + ".lock();\n";
    sb += "    defer " + query.table + ".unlock();\n";

    if query.orderings.isEmpty() {
      sb += "    ref candidates = " + query.table + ".rows;\n";
    } else {
      sb += "    var matching: list(" + table.recordName + ");\n";
      sb += "    for row in " + query.table + ".rows do\n";
      sb += "      if " + condition + " then matching.pushBack(row);\n";
      sb += "    var candidates = matching.toArray();\n";
      sb += "    sort(candidates, comparator = new " + comparatorName(query) + "());\n";
    }

    const guard = if query.orderings.isEmpty() then condition else "true";

    if returnsOne {
      if bounded then sb += "    var skipped = 0;\n";
      sb += "    for row in candidates {\n";
      sb += "      if !(" + guard + ") then continue;\n";
      if !query.offsetOperand.isEmpty() {
        sb += "      if skipped < " + query.offsetOperand + " {\n";
        sb += "        skipped += 1;\n";
        sb += "        continue;\n";
        sb += "      }\n";
      }
      sb += "      result = " + projectExpression(query, "row") + ";\n";
      sb += "      return true;\n";
      sb += "    }\n";
      sb += "    return false;\n";
    } else {
      sb += "    var picked: list(" + query.rowType() + ");\n";
      if !query.offsetOperand.isEmpty() then sb += "    var skipped = 0;\n";
      sb += "    for row in candidates {\n";
      sb += "      if !(" + guard + ") then continue;\n";
      if !query.offsetOperand.isEmpty() {
        sb += "      if skipped < " + query.offsetOperand + " {\n";
        sb += "        skipped += 1;\n";
        sb += "        continue;\n";
        sb += "      }\n";
      }
      if !query.limitOperand.isEmpty() then
        sb += "      if picked.size >= " + query.limitOperand + " then break;\n";
      sb += "      picked.pushBack(" + projectExpression(query, "row") + ");\n";
      sb += "    }\n";
      sb += "    return picked;\n";
    }
    sb += "  }\n\n";
    return sb;
  }

  private proc insertProc(const ref query: Query, const ref schema: Schema): string throws {
    const table = schema.tables[query.table];
    const returnsRow = query.shape == ResultShape.one;

    var sb = "  proc " + query.name + "(" + signature(query) + "): " +
              (if returnsRow then table.recordName else "int") + " throws {\n";
    sb += "    var row = new " + table.recordName + "();\n";
    for i in 0..<query.insertColumns.size do
      sb += "    row." + query.insertColumns[i] + " = " + query.insertValues[i] + ";\n";
    if returnsRow {
      sb += "    return " + query.table + ".insert(row);\n";
    } else {
      sb += "    " + query.table + ".insert(row);\n";
      sb += "    return 1;\n";
    }
    sb += "  }\n\n";
    return sb;
  }

  private proc updateProc(const ref query: Query, const ref schema: Schema): string throws {
    const table = schema.tables[query.table];
    const returnsRow = query.shape == ResultShape.one;
    const condition = conditionExpression(query, "row");

    var sb = "  proc " + query.name + "(" + signature(query) +
              (if returnsRow then (if query.params.isEmpty() then "" else ", ") +
                                  "ref result: " + table.recordName
               else "") + "): " + (if returnsRow then "bool" else "int") + " {\n";
    sb += "    " + query.table + ".lock();\n";
    sb += "    defer " + query.table + ".unlock();\n";
    sb += "    var affected = 0;\n";
    sb += "    for i in 0..<" + query.table + ".rows.size {\n";
    sb += "      const row = " + query.table + ".rows[i];\n";
    sb += "      if !(" + condition + ") then continue;\n";
    for assignment in query.assignments {
      sb += "      " + query.table + ".rows[i]." + assignment.column + " = " +
             assignment.operand + assignment.delta + ";\n";
    }
    sb += "      affected += 1;\n";
    if returnsRow {
      sb += "      result = " + query.table + ".rows[i];\n";
      sb += "      " + query.table + ".save();\n";
      sb += "      return true;\n";
    }
    sb += "    }\n";
    sb += "    if affected > 0 then " + query.table + ".save();\n";
    sb += "    return " + (if returnsRow then "false" else "affected") + ";\n";
    sb += "  }\n\n";
    return sb;
  }

  private proc deleteProc(const ref query: Query, const ref schema: Schema): string throws {
    const table = schema.tables[query.table];
    const returnsOne = query.shape == ResultShape.one;
    const condition = conditionExpression(query, "row");

    var sb = "  proc " + query.name + "(" + signature(query) + "): " +
              (if returnsOne then "bool" else "int") + " {\n";
    sb += "    " + query.table + ".lock();\n";
    sb += "    defer " + query.table + ".unlock();\n";
    sb += "    var kept: list(" + table.recordName + ");\n";
    sb += "    var removed = 0;\n";
    sb += "    for row in " + query.table + ".rows {\n";
    if returnsOne then
      sb += "      if removed == 0 && " + condition + " {\n";
    else
      sb += "      if " + condition + " {\n";
    sb += "        removed += 1;\n";
    sb += "        continue;\n";
    sb += "      }\n";
    sb += "      kept.pushBack(row);\n";
    sb += "    }\n";
    sb += "    if removed > 0 {\n";
    sb += "      " + query.table + ".rows = kept;\n";
    sb += "      " + query.table + ".save();\n";
    sb += "    }\n";
    sb += "    return " + (if returnsOne then "removed > 0" else "removed") + ";\n";
    sb += "  }\n\n";
    return sb;
  }
}
