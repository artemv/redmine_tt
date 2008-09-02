mysql -u redmine -predmine redmine < redmine.sql
rake redmine:migrate_from_trac --trace
