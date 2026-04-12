# Implementation Plan: [FEATURE_NAME]

**Based on Spec**: [link to FEATURE_SPEC.md]
**Created**: [DATE]
**Claude Code Session**: [SESSION_ID]
**Status**: Draft | Approved | In Progress | Complete

## Architecture Decisions
- [Decision 1]: [Rationale]
- [Decision 2]: [Rationale]

## Technology Stack
- **Frontend**: Flutter (web/mobile)
- **Backend**: FastAPI (Python)
- **Database**: Supabase PostgreSQL
- **Server**: Nginx + Tailscale on Zorin OS
- **AI**: Gemma 4 E2B via Ollama (if applicable)

## Component Breakdown

### Backend Components

#### Component 1: [Name]
**Purpose**: [What it does]
**Dependencies**: [Other components]
**Files Modified/Created**:
- `backend/app/routers/[name].py`
- `backend/app/models/[name].py`
- `backend/app/schemas/[name].py`

**Key Functions**:
```python
# Pseudocode
async def endpoint_name(params):
    # Implementation sketch
    pass
```

### Frontend Components

#### Component 2: [Name]
**Purpose**: [What it does]
**Dependencies**: [Other components]
**Files Modified/Created**:
- `lib/screens/[name]_screen.dart`
- `lib/widgets/[name]_widget.dart`
- `lib/providers/[name]_provider.dart`

**Key Widgets**:
```dart
// Pseudocode
class WidgetName extends StatelessWidget {
  // Implementation sketch
}
```

## Database Changes

### New Tables
```sql
CREATE TABLE IF NOT EXISTS table_name (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- columns
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### Migrations
```sql
-- Migration SQL here
ALTER TABLE existing_table ADD COLUMN new_column VARCHAR(255);
```

### RLS Policies
```sql
-- Row Level Security policies
CREATE POLICY "policy_name" ON table_name
    FOR SELECT USING (auth.uid() = user_id);
```

## API Changes

### New Endpoints
- `POST /api/v1/endpoint` - [Description]
  - **Request**: `{field: value}`
  - **Response**: `{result: data}`
  - **Auth**: Required (role: [role])

### Modified Endpoints
- `GET /api/v1/endpoint` - [What changed]

## User Interface Changes
- [Screen/Widget modifications]
- [RTL considerations if Arabic content]

## Testing Strategy

### Backend Tests
- [ ] Unit tests for [endpoints]
  - `tests/test_[name].py`
- [ ] Integration tests for [flows]

### Frontend Tests
- [ ] Widget tests for [components]
  - `test/widgets/[name]_test.dart`
- [ ] Integration tests for [screens]

### E2E Tests
- [ ] User flow: [description]

## Deployment Considerations
- [ ] Nginx configuration changes
- [ ] Environment variables
- [ ] Database migrations
- [ ] Systemd service updates (if applicable)

## Risk Assessment
- **High Risk**: [Item] - [Mitigation]
- **Medium Risk**: [Item] - [Mitigation]
- **Low Risk**: [Item] - [Mitigation]

## Rollback Plan
1. [Step to revert changes]
2. [Database rollback if needed]
3. [Service restart procedures]

## Approval
- [ ] Plan reviewed for complexity
- [ ] No over-engineering detected
- [ ] All dependencies identified
- [ ] Ready for task breakdown

---
**Handoff Note**: This plan is ready for OpenCode implementation.
