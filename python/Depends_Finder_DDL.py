import sqlparse
import re
import os
from collections import defaultdict


class StoredProcedure:
    """ Object to store stored procedure details. """

    def __init__(self, name, tables, columns):
        self.name = name
        self.tables = set(tables)  # Ensure unique tables
        self.columns = columns

    def __str__(self):
        return f"Stored Procedure: {self.name}\nTables: {list(self.tables)}"


def read_sql_file(file_path):
    """ Reads an SQL file and returns its content as a string. """
    with open(file_path, "r", encoding="utf-8") as file:
        return file.read()


def extract_stored_procedure_name(sql):
    """ Extracts the stored procedure name from the SQL definition. """
    match = re.search(r"CREATE\s+PROCEDURE\s+([\w\.\[\]]+)", sql, re.IGNORECASE)
    return match.group(1).strip('[]') if match else "Unknown_Procedure"


def extract_tables_and_columns(sql):
    """
    Extracts fully qualified table names and their columns from a SQL stored procedure.
    Supports both bracketed and non-bracketed table identifiers.
    """
    tables = {}
    columns = defaultdict(set)

    # ✅ Format SQL for consistent parsing
    sql = sqlparse.format(sql, strip_comments=True, keyword_case='upper')

    # ✅ Updated regex to support:
    # - Fully qualified table names (Database.Schema.Table)
    # - Optional square brackets around table names and aliases
    table_pattern = re.compile(r"""
        (?:FROM|JOIN)                 # Match FROM or JOIN
        \s+\[?([\w]+)\]?              # Match optional bracketed Database name
        \.\[?([\w]+)\]?               # Match optional bracketed Schema name
        \.\[?([\w]+)\]?               # Match optional bracketed Table name
        (?:\s+AS\s+\[?([\w]+)\]?)?    # Match optional alias
    """, re.IGNORECASE | re.VERBOSE)

    # ✅ Extract table names and aliases
    for match in table_pattern.findall(sql):
        db, schema, table, alias = match
        full_table_name = f"{db}.{schema}.{table}"
        tables[alias or full_table_name] = full_table_name  # Store alias if present

    # ✅ Extract columns from SELECT clause
    select_pattern = re.compile(r"\[?([\w]+)\]?\.\[?([\w]+)\]?", re.IGNORECASE)
    select_match = re.search(r"SELECT\s+(.*?)\s+FROM", sql, re.DOTALL | re.IGNORECASE)

    if select_match:
        select_clause = select_match.group(1)
        for alias, column in select_pattern.findall(select_clause):
            table_name = tables.get(alias, alias)  # Resolve alias to full name
            columns[table_name].add(column.strip('[]'))

    # ✅ Extract columns from JOIN conditions
    join_pattern = re.compile(r"ON\s+\[?([\w]+)\]?\.\[?([\w]+)\]?\s*=\s*\[?([\w]+)\]?\.\[?([\w]+)\]?", re.IGNORECASE)
    for left_table_alias, left_col, right_table_alias, right_col in join_pattern.findall(sql):
        left_table = tables.get(left_table_alias, left_table_alias)
        right_table = tables.get(right_table_alias, right_table_alias)
        columns[left_table].add(left_col.strip('[]'))
        columns[right_table].add(right_col.strip('[]'))

    return set(tables.values()), columns


def find_table_script_path(repo_path, table_name, defaultDB):
    """
    Locate the corresponding CREATE TABLE script based on the repo structure.
    Expected structure: {repo_path}/{database}/{schema}/Tables/{schema}.{table}.sql
    """
    parts = table_name.split(".")
    if len(parts) == 3:  # Database.Schema.Table
        db_name, schema, table = parts
    elif len(parts) == 2:  # Schema.Table (assume default DB)
        db_name, schema, table = defaultDB, parts[0], parts[1]
    else:  # Table only (assume default DB/schema)
        db_name, schema, table = defaultDB, "dbo", parts[0]

    script_path = os.path.join(repo_path, db_name, schema, "Tables", f"{schema}.{table}.sql")

    # Debugging statement to check if the script path is correct
    print(f"Looking for script at: {script_path}")

    if os.path.exists(script_path):
        return script_path
    else:
        print(f"WARNING: Table script not found for {table_name} at {script_path}")
        return None


def extract_column_data_types(create_table_script):
    """ Parses a CREATE TABLE statement and extracts column names with their actual data types. """
    if not create_table_script or not isinstance(create_table_script, str):
        print(f"ERROR: Invalid CREATE TABLE script content. Received: {type(create_table_script)}")
        return {}

    column_types = {}

    # Convert script into a single line
    normalized_script = " ".join(create_table_script.split()).replace(", NULL", "")

    #   Updated regex to handle:
    # - Square brackets [ColumnName]
    # - Data types with spaces (e.g., VARCHAR (255))
    # - Removing trailing NULLs and extra commas
    column_pattern = r"\[([\w]+)\]\s+([\w\s\(\)]+)"

    try:
        matches = re.findall(column_pattern, normalized_script)
        if not matches:
            print("WARNING: No columns found in CREATE TABLE script. Check file format.")

        for match in matches:
            column_name, data_type = match
            column_types[column_name] = data_type.strip()

    except Exception as e:
        print(f"ERROR: Regex processing failed: {e}")
        return {}

    return column_types


def generate_ddl_for_tables(repo_path, tables, columns):
    """
    Generates DDL statements for the extracted tables and columns,
    replacing VARCHAR(255) with actual data types from the local repo.
    """
    ddl_statements = []

    for table in sorted(tables):
        script_path = find_table_script_path(repo_path, table,defaultDB)
        column_types = {}

        if script_path:
            try:
                if not os.path.exists(script_path) or os.path.getsize(script_path) == 0:
                    print(f"WARNING: {script_path} does not exist or is empty.")
                    create_table_script = None
                else:
                    with open(script_path, "r", encoding="utf-8") as file:
                        create_table_script = file.read().strip()
                        if not create_table_script:
                            print(f"WARNING: {script_path} is empty after reading.")
                            create_table_script = None
                    column_types = extract_column_data_types(create_table_script)

            except UnicodeDecodeError:
                print(f"ERROR: Unable to read {script_path} due to encoding issues.")
                create_table_script = None
            except Exception as e:
                print(f"ERROR: Failed to read {script_path}: {e}")
                create_table_script = None
        else:
            print(f"WARNING: No script found for {table}, using default types.")

        ddl = f"CREATE TABLE {table} (\n"
        col_defs = [
            f"    {col} {column_types.get(col, 'VARCHAR(255)')}"
            for col in sorted(columns.get(table, []))
        ]
        ddl += ",\n".join(col_defs) + "\n);" if col_defs else ");"
        ddl_statements.append(ddl)

    return "\n\n".join(ddl_statements)

def generate_ddl_for_stored_proc(sp_name, referenced_tables):
    """ Generates DDL for stored procedure table with referenced tables as TABLE type columns. """
    ddl = f"CREATE TABLE {sp_name} (\n"
    table_columns = [f"    {table} TABLE" for table in sorted(referenced_tables)]
    ddl += ",\n".join(table_columns) + "\n);" if table_columns else ");"
    return ddl + "\n"


# Main execution
repo_path = ""
defaultDB = "ThisDB"
#repo_path = input("Enter the top-level path for the database repository: ").strip()
sql_file_path = ""

sql_procedure = read_sql_file(sql_file_path)
sp_name = extract_stored_procedure_name(sql_procedure)
tables, columns = extract_tables_and_columns(sql_procedure)
sp = StoredProcedure(name=sp_name, tables=tables, columns=columns)

ddl_proc = generate_ddl_for_stored_proc(sp.name, sp.tables)
ddl_tables = generate_ddl_for_tables(repo_path, sp.tables, sp.columns)

# Print and save output
print("\nGenerated DDL Statements:\n")
print(ddl_proc)
print(ddl_tables)
with open("output.txt", "w", encoding="utf-8") as file:
    file.write(ddl_proc + "\n\n" + ddl_tables)
print("\nDDL statements saved to: output.ddl")
