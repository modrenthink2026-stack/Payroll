import {readFileSync} from 'node:fs';

// Historical upgrades already included in payroll.sql must not be replayed.
for(const file of ['payroll.sql','system-users-upgrade.sql','salary-payment-holds-upgrade.sql','platform-admin-upgrade.sql','monthly-attendance-upgrade.sql']){
 process.stdout.write(`\n-- ${file}\n`+readFileSync(new URL('../database/'+file,import.meta.url),'utf8')+'\n');
}
