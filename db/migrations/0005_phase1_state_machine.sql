-- ================================================================
-- 0005_phase1_state_machine.sql
-- Phase 1: 状態遷移バリデーション
--
-- 0004 で定義した4つのエンティティの状態遷移を検証する。
-- 不正な遷移は EXCEPTION で拒否し、正常な遷移ではタイムスタンプを自動更新。
--
-- 対象:
--   staffing_requests   (request_status)
--   proposals           (proposal_status)
--   assignments         (assignment_status)
--   invoices            (invoice_status)
--
-- 注意:
--   - INSERT は初期状態を強制しない（draft / created / confirmed / draft）
--   - 直接 UPDATE での status 変更時のみバリデーションを実行
--   - 不正遷移時は SQLSTATE '22023'（invalid_parameter_value）相当
-- ================================================================

-- ================================================================
-- 1. staffing_requests の状態遷移
-- ================================================================
CREATE OR REPLACE FUNCTION validate_request_transition()
RETURNS TRIGGER AS $$
BEGIN
  -- ステータス未変更ならスキップ
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- キャンセルは進行中の状態からならいつでも可
  IF NEW.status = 'cancelled' AND OLD.status NOT IN ('paid', 'cancelled') THEN
    -- cancelled_at と cancelled_by は呼び出し側で設定
    IF NEW.cancelled_at IS NULL THEN
      NEW.cancelled_at := NOW();
    END IF;
    RETURN NEW;
  END IF;

  -- 通常の有効遷移
  IF NOT (
    (OLD.status = 'draft'              AND NEW.status = 'submitted') OR
    (OLD.status = 'submitted'          AND NEW.status = 'under_review') OR
    (OLD.status = 'under_review'       AND NEW.status IN ('accepted', 'rejected')) OR
    (OLD.status = 'accepted'           AND NEW.status = 'proposing') OR
    (OLD.status = 'proposing'          AND NEW.status IN ('partially_assigned', 'fully_assigned')) OR
    (OLD.status = 'partially_assigned' AND NEW.status IN ('fully_assigned', 'in_progress')) OR
    (OLD.status = 'fully_assigned'     AND NEW.status = 'in_progress') OR
    (OLD.status = 'in_progress'        AND NEW.status = 'completion_pending') OR
    (OLD.status = 'completion_pending' AND NEW.status IN ('confirmed', 'in_progress')) OR
    (OLD.status = 'confirmed'          AND NEW.status = 'invoiced') OR
    (OLD.status = 'invoiced'           AND NEW.status = 'paid')
  ) THEN
    RAISE EXCEPTION 'Invalid staffing_requests transition: % -> %',
      OLD.status, NEW.status
      USING ERRCODE = '22023';
  END IF;

  -- 状態に応じたタイムスタンプ自動更新
  IF NEW.status = 'submitted' AND NEW.submitted_at IS NULL THEN
    NEW.submitted_at := NOW();
  END IF;
  IF NEW.status = 'under_review' AND NEW.reviewed_at IS NULL THEN
    NEW.reviewed_at := NOW();
  END IF;
  IF NEW.status = 'accepted' AND NEW.accepted_at IS NULL THEN
    NEW.accepted_at := NOW();
  END IF;
  IF NEW.status IN ('fully_assigned', 'in_progress') AND NEW.fulfilled_at IS NULL THEN
    NEW.fulfilled_at := NOW();
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_request_transition ON staffing_requests;
CREATE TRIGGER trg_validate_request_transition
  BEFORE UPDATE OF status ON staffing_requests
  FOR EACH ROW EXECUTE FUNCTION validate_request_transition();

COMMENT ON FUNCTION validate_request_transition()
  IS 'staffing_requests.status の遷移を検証し不正な変更を拒否する';

-- ================================================================
-- 2. proposals の状態遷移
-- ================================================================
CREATE OR REPLACE FUNCTION validate_proposal_transition()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- 終了状態（facility_accepted/declined, worker_declined, withdrawn, expired）からの変更は不可
  IF OLD.status IN (
    'worker_declined', 'facility_accepted', 'facility_declined',
    'withdrawn', 'expired'
  ) THEN
    RAISE EXCEPTION 'proposals is in terminal state: %', OLD.status
      USING ERRCODE = '22023';
  END IF;

  -- withdrawn / expired はどの非終了状態からでも可能
  IF NEW.status IN ('withdrawn', 'expired') THEN
    RETURN NEW;
  END IF;

  IF NOT (
    (OLD.status = 'created'              AND NEW.status = 'worker_contacted') OR
    (OLD.status = 'worker_contacted'     AND NEW.status IN ('worker_accepted', 'worker_declined')) OR
    (OLD.status = 'worker_accepted'      AND NEW.status = 'proposed_to_facility') OR
    (OLD.status = 'proposed_to_facility' AND NEW.status IN ('facility_accepted', 'facility_declined'))
  ) THEN
    RAISE EXCEPTION 'Invalid proposals transition: % -> %',
      OLD.status, NEW.status
      USING ERRCODE = '22023';
  END IF;

  -- ワーカー応答時刻の自動更新
  IF NEW.status IN ('worker_accepted', 'worker_declined')
     AND NEW.worker_responded_at IS NULL THEN
    NEW.worker_responded_at := NOW();
  END IF;
  -- 施設応答時刻の自動更新
  IF NEW.status IN ('facility_accepted', 'facility_declined')
     AND NEW.facility_responded_at IS NULL THEN
    NEW.facility_responded_at := NOW();
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_proposal_transition ON proposals;
CREATE TRIGGER trg_validate_proposal_transition
  BEFORE UPDATE OF status ON proposals
  FOR EACH ROW EXECUTE FUNCTION validate_proposal_transition();

COMMENT ON FUNCTION validate_proposal_transition()
  IS 'proposals.status の遷移を検証し不正な変更を拒否する';

-- ================================================================
-- 3. assignments の状態遷移
-- ================================================================
CREATE OR REPLACE FUNCTION validate_assignment_transition()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- 終了状態
  IF OLD.status IN ('completion_confirmed', 'cancelled', 'no_show') THEN
    RAISE EXCEPTION 'assignments is in terminal state: %', OLD.status
      USING ERRCODE = '22023';
  END IF;

  -- cancelled は disputed と confirmed からのみ
  IF NEW.status = 'cancelled' THEN
    IF OLD.status NOT IN ('confirmed', 'disputed', 'checked_in') THEN
      RAISE EXCEPTION 'cannot cancel assignment in state %', OLD.status
        USING ERRCODE = '22023';
    END IF;
    IF NEW.cancelled_at IS NULL THEN
      NEW.cancelled_at := NOW();
    END IF;
    RETURN NEW;
  END IF;

  -- no_show は confirmed からのみ
  IF NEW.status = 'no_show' THEN
    IF OLD.status <> 'confirmed' THEN
      RAISE EXCEPTION 'no_show only valid from confirmed, was %', OLD.status
        USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
  END IF;

  IF NOT (
    (OLD.status = 'confirmed'            AND NEW.status = 'checked_in') OR
    (OLD.status = 'checked_in'           AND NEW.status IN ('checked_out', 'disputed')) OR
    (OLD.status = 'checked_out'          AND NEW.status IN ('completion_reported', 'disputed')) OR
    (OLD.status = 'completion_reported'  AND NEW.status IN ('completion_confirmed', 'disputed')) OR
    (OLD.status = 'disputed'             AND NEW.status = 'completion_confirmed')
  ) THEN
    RAISE EXCEPTION 'Invalid assignments transition: % -> %',
      OLD.status, NEW.status
      USING ERRCODE = '22023';
  END IF;

  -- check-in/out のタイムスタンプ自動補完
  IF NEW.status = 'checked_in' AND NEW.checked_in_at IS NULL THEN
    NEW.checked_in_at := NOW();
  END IF;
  IF NEW.status = 'checked_out' AND NEW.checked_out_at IS NULL THEN
    NEW.checked_out_at := NOW();
  END IF;
  IF NEW.status = 'completion_reported' AND NEW.worker_reported_at IS NULL THEN
    NEW.worker_reported_at := NOW();
  END IF;
  IF NEW.status = 'completion_confirmed' AND NEW.facility_confirmed_at IS NULL THEN
    NEW.facility_confirmed_at := NOW();
  END IF;
  IF NEW.status = 'disputed' AND NEW.dispute_opened_at IS NULL THEN
    NEW.dispute_opened_at := NOW();
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_assignment_transition ON assignments;
CREATE TRIGGER trg_validate_assignment_transition
  BEFORE UPDATE OF status ON assignments
  FOR EACH ROW EXECUTE FUNCTION validate_assignment_transition();

COMMENT ON FUNCTION validate_assignment_transition()
  IS 'assignments.status の遷移を検証し不正な変更を拒否する';

-- ================================================================
-- 4. invoices の状態遷移
-- ================================================================
CREATE OR REPLACE FUNCTION validate_invoice_transition()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- 終了状態
  IF OLD.status IN ('paid', 'void') THEN
    RAISE EXCEPTION 'invoices is in terminal state: %', OLD.status
      USING ERRCODE = '22023';
  END IF;

  IF NOT (
    (OLD.status = 'draft'    AND NEW.status IN ('issued', 'void')) OR
    (OLD.status = 'issued'   AND NEW.status IN ('paid', 'overdue', 'void')) OR
    (OLD.status = 'overdue'  AND NEW.status IN ('paid', 'void'))
  ) THEN
    RAISE EXCEPTION 'Invalid invoices transition: % -> %',
      OLD.status, NEW.status
      USING ERRCODE = '22023';
  END IF;

  -- 発行・支払日の自動補完
  IF NEW.status = 'issued' AND NEW.issue_date IS NULL THEN
    NEW.issue_date := CURRENT_DATE;
  END IF;
  IF NEW.status = 'paid' AND NEW.paid_date IS NULL THEN
    NEW.paid_date := CURRENT_DATE;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validate_invoice_transition ON invoices;
CREATE TRIGGER trg_validate_invoice_transition
  BEFORE UPDATE OF status ON invoices
  FOR EACH ROW EXECUTE FUNCTION validate_invoice_transition();

COMMENT ON FUNCTION validate_invoice_transition()
  IS 'invoices.status の遷移を検証し不正な変更を拒否する';

-- ================================================================
-- 5. 補助関数：終端状態判定
-- ================================================================
CREATE OR REPLACE FUNCTION is_request_terminal(s request_status)
RETURNS boolean AS $$
  SELECT s IN ('paid', 'cancelled', 'rejected');
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION is_proposal_terminal(s proposal_status)
RETURNS boolean AS $$
  SELECT s IN ('worker_declined', 'facility_accepted', 'facility_declined',
               'withdrawn', 'expired');
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION is_assignment_terminal(s assignment_status)
RETURNS boolean AS $$
  SELECT s IN ('completion_confirmed', 'cancelled', 'no_show');
$$ LANGUAGE SQL IMMUTABLE;

CREATE OR REPLACE FUNCTION is_invoice_terminal(s invoice_status)
RETURNS boolean AS $$
  SELECT s IN ('paid', 'void');
$$ LANGUAGE SQL IMMUTABLE;

COMMENT ON FUNCTION is_request_terminal(request_status)    IS '依頼が終端状態かを判定';
COMMENT ON FUNCTION is_proposal_terminal(proposal_status)  IS '提案が終端状態かを判定';
COMMENT ON FUNCTION is_assignment_terminal(assignment_status) IS 'アサインが終端状態かを判定';
COMMENT ON FUNCTION is_invoice_terminal(invoice_status)    IS '請求書が終端状態かを判定';
