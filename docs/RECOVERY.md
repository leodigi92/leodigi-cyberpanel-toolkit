# Recovery runbook

1. Stop the affected website or put it in maintenance mode if consistency matters.
2. Run `toolkitctl backup list PROFILE` and select a known-good snapshot.
3. Restore to a new absolute directory, never `/` or a live document root.
4. Verify checksums, scan restored files and inspect the included manifest.
5. Create a fresh backup of the damaged live state for forensic retention.
6. Copy only reviewed files into a newly created CyberPanel website.
7. Import the selected `.sql.gz` dump into a new database.
8. update `wp-config.php`, run WP-CLI search-replace if the domain changed, and repair permissions.
9. Test via hosts-file override before changing DNS.
10. Record the root cause and rotate any credentials exposed during the incident.
