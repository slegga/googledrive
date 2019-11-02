-- 1 up
create table if not exists files_state (
  id    integer primary key autoincrement,
  loc_pathfile text,
  loc_mod_epoch integer,
  loc_size integer,
  loc_md5_hex  text,
  loc_tmp_md5_hex text,
  rem_file_id text,
  rem_parent_id text,
  rem_filename text,
  rem_mod_epoch integer,
  rem_md5_hex text,
  act_epoch text,
  act_action text
);

CREATE UNIQUE INDEX loc_pathfile
ON files_state(loc_pathfile);

create table if not exists replication_state_int (
  id    integer primary key autoincrement,
  key text,
  value integer
);


-- 1 down
drop table if exists files_state;
drop table if exists replication_state_int;
