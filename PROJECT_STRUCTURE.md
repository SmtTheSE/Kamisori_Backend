# Kamisori Backend - Project Structure

## 📁 Root Directory

```
Kamisori Backend/
├── 📄 README.md                          # Main project documentation
├── 📄 DATABASE_README.md                 # Database schema reference
├── 📄 database_schema.sql                # Consolidated SQL schema
├── 📄 COMPLETE_DEPLOYMENT_GUIDE.md       # Deployment instructions
├── 📄 SETUP_GUIDE.md                     # Initial setup guide
├── 📄 API_DOCUMENTATION.md               # API endpoints reference
├── 📄 FRONTEND_INTEGRATION_EXAMPLE.md    # Frontend integration guide
├── 📄 KBZ_PAY_INTEGRATION_EXAMPLE.md     # Payment integration guide
├── 📄 SUPABASE_TESTING.md                # Testing guide
├── 📄 admin-panel.html                   # Admin panel demo
├── 📄 demo-frontend.html                 # Customer frontend demo
├── 📄 test_supabase.js                   # Test script
├── 📄 package.json                       # Node dependencies
├── 📄 package-lock.json                  # Locked dependencies
├── 📁 supabase/                          # Supabase configuration
│   ├── 📁 functions/                     # Edge Functions
│   └── 📁 migrations/                    # Database migrations (001-020)
├── 📁 kamisori-swagger/                  # API documentation
├── 📁 utils/                             # Utility scripts
└── 📁 docs/                              # Additional documentation
```

## 📚 Documentation Guide

### For New Developers
1. **Start here**: `README.md` - Project overview and quick start
2. **Database**: `DATABASE_README.md` - Complete schema documentation
3. **Setup**: `SETUP_GUIDE.md` - Environment setup instructions
4. **Deploy**: `COMPLETE_DEPLOYMENT_GUIDE.md` - Production deployment

### For Frontend Developers
1. `API_DOCUMENTATION.md` - All available endpoints
2. `FRONTEND_INTEGRATION_EXAMPLE.md` - React/TypeScript examples
3. `KBZ_PAY_INTEGRATION_EXAMPLE.md` - Payment flow implementation

### For Backend Developers
1. `database_schema.sql` - Complete SQL schema reference
2. `DATABASE_README.md` - Architecture and security model
3. `supabase/migrations/` - Migration history

## 🗄️ Database Migrations

All migrations are in `supabase/migrations/`:

| File | Purpose |
|------|---------|
| `001_enable_pg_net_extension.sql` | Enable HTTP requests |
| `009_clean_schema_setup.sql` | Core tables and types |
| `010_business_logic_functions.sql` | Checkout and management |
| `011_admin_reporting_functions.sql` | Admin queries |
| `012_security_policies_triggers.sql` | RLS policies |
| `013_storage_policies.sql` | File storage |
| `014_admin_notifications_monitoring.sql` | Notifications |
| `015_admin_delete_functions.sql` | Delete operations |
| `016_cleanup_old_orders_function.sql` | Maintenance |
| `017_fix_security_lint_errors.sql` | RLS security fixes |
| `018_fix_security_warnings.sql` | Function security |
| `019_performance_and_final_security_fixes.sql` | Performance indices |
| `020_rls_performance_and_policy_cleanup.sql` | RLS optimization |

**Note**: For a consolidated view of the entire schema, see `database_schema.sql`

## 🚀 Quick Commands

```bash
# Install dependencies
npm install

# Run tests
node test_supabase.js

# Deploy migrations
supabase db push

# Start local development
supabase start
```

## 📝 Notes

- All migration files are required for proper deployment
- `database_schema.sql` is for reference only (not a migration)
- Demo HTML files are for testing and can be removed in production
- Edge Functions are in `supabase/functions/`
