mysql -u redminedev -predminedev redminedev < redmine.sql
rake db:migrate
rake redmine:migrate_from_trac_08_4 VRG vrg "VRG" --trace
