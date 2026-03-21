-- Create work_order_comments table
CREATE TABLE IF NOT EXISTS public.work_order_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    work_order_id UUID REFERENCES public.work_orders(id) ON DELETE CASCADE,
    author_email TEXT NOT NULL,
    author_name TEXT,
    body TEXT NOT NULL,
    type TEXT DEFAULT 'comment',
    meta JSONB,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Create index
CREATE INDEX IF NOT EXISTS idx_work_order_comments_wo ON public.work_order_comments(work_order_id);

-- Create work_order_attachments table
CREATE TABLE IF NOT EXISTS public.work_order_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    work_order_id UUID REFERENCES public.work_orders(id) ON DELETE CASCADE,
    file_name TEXT NOT NULL,
    file_url TEXT NOT NULL,
    file_type TEXT,
    uploaded_by TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_work_order_attachments_wo ON public.work_order_attachments(work_order_id);