"""Check the planning package only; no application runtime is implemented."""
import csv
from decimal import Decimal
from pathlib import Path

root = Path(__file__).resolve().parents[1]
req = (root / 'docs/requirements.md').read_text()
for name in ['Staff Master', 'Basic', 'DA', 'HRA', 'PF', 'ESI', 'TDS',
             'Attendance', 'Leave Master', 'login', 'Payslips', 'HR', 'Accountant',
             'biometric', 'late-coming', 'early-going', 'Monthly salaries',
             'Reports', 'Security Deposit', 'other authorized deductions']:
    assert name.lower() in req.lower(), f'Missing scope: {name}'
for name in ['inactive until', 'earned gross salary', 'employer costs',
             'deduct the same time twice', 'idempotent', 'snapshots', 'atomically']:
    assert name in req.lower(), f'Missing safeguard: {name}'
for filename in ['staff-master.csv', 'attendance-punches.csv', 'leave-master.csv',
                 'assessment-master.csv', 'increment-recommendations.csv', 'letter-register.csv']:
    with (root / 'templates' / filename).open(newline='') as f:
        rows = list(csv.reader(f))
    assert len(rows) == 1, 'Starter templates must contain no staff data'
    assert rows[0][0] == 'company_code'
    assert len(rows[0]) == len(set(rows[0])), 'Duplicate column'
gross = Decimal('30000')
deposit = gross * Decimal('0.10')
assert deposit == Decimal('3000')
assert gross - deposit - Decimal('2500') == Decimal('24500')
life = (root / 'docs/employee-lifecycle.md').read_text().lower()
for name in ['offer letter', 'appointment letter', 'staff assessment',
             'increment recommendation', 'regularisation', 'termination letter',
             'relieving letter', 'experience letter', 'probation extension',
             'promotion', 'resignation acceptance', 'final settlement',
             'does not disable login', 'exactly one salary version', 'linked replacement']:
    assert name in life, f'Missing lifecycle coverage: {name}'
print('PASS: original and lifecycle scope/safeguard presence, six blank CSV templates and illustration arithmetic.')
print('NOT RUN: application, payroll/tax engine, login, device, performance or filing tests.')
