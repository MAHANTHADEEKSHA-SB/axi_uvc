# Single AXI UVC — architecture and AI handoff

This folder governs **one reusable AXI UVC POC** with a Manager and a Subordinate role, developed at `poc/axi_uvc/`. The *same* AXI UVC is instantiated with two width configurations (A: AW=32/DW=32/ID 4/4, B: AW=40/DW=64/ID 6/5) to test parameter independence, and runs AXI4 or AXI4-Lite by configuration. We are **not building a multi-UVC framework** or generating APB/AHB/UCIe components here.

The templates and instructions come from the `apb_uvc` repository (`dev`, commit `b406d6a`) as adapted in the `AHB-UVC` repository (`dev`, commit `73f7d33`), adapted to AXI on the owner's request (`DECISION_LOG.md` D-001). The AXI-specific decisions taken earlier (`../ARCHITECTURE_DECISIONS.md`, PR #14) stay in force as A-1..A-11; where this architecture changes one of them, the change is a proposal awaiting the owner's confirmation (S-1..S-6).

## Read in order

0. [SESSION_SUMMARY.md](SESSION_SUMMARY.md): one-page orientation, session log and a start prompt for a new chat (summary only; the documents below govern).
1. [AGENTS.md](AGENTS.md): what every model/engineer must read and how to hand off.
2. [DECISION_LOG.md](DECISION_LOG.md): every owner decision, dated, with where it is applied, the AXI decisions A-1..A-11 and the open proposals S-1..S-6; overrides the documents below.
3. [CODING_GUIDELINES.md](CODING_GUIDELINES.md): **mandatory** SystemVerilog/UVM coding standard, Git rules and pre-commit checklist.
4. [ARCHITECTURE_CONTRACT.md](ARCHITECTURE_CONTRACT.md): AXI-only agreed architectural rules and unresolved decisions.
5. [ADR-001](ADR-001-HVL-PROXY-PLACEMENT.md): HVL concrete proxies over parameterized BFM virtual handles.
6. [ADR-002](ADR-002-SEPARATE-DRIVE-OBSERVE-APIS.md): separate abstract capabilities — drive, respond (amendment AXI-1) and observe — and BFMs sharing one signal interface.
7. [DIRECTORY_ARCHITECTURE.md](DIRECTORY_ARCHITECTURE.md): self-contained AXI UVC distribution, example directory, and where the PR #14 placeholders went.
8. [CLAUDE_GENERATION_PROMPT.md](CLAUDE_GENERATION_PROMPT.md): single-AXI implementation brief.
9. [WORK_STATUS.md](WORK_STATUS.md): real completed/pending work, latest checkpoint and evidence.
10. [REVIEW_FEEDBACK.md](REVIEW_FEEDBACK.md): independent review findings and required retests.
11. [AXI_PROTOCOL_CONTRACT.md](AXI_PROTOCOL_CONTRACT.md): AXI-001 protocol strategy, signal matrix, rules, policies, reset assumptions and transaction format traced to ARM IHI 0022.

## Deliverable boundary

One `poc/axi_uvc/` directory ships its own **AXI interface, Manager, Subordinate and monitor BFMs, HVL proxies, UVM classes of both roles, sequences, coverage, filelists and usage example**. SV interfaces compile as HDL units; the UVM class definitions compile in packages. A UVC deliverable is **not one giant SV package**.

## Current status

Architecture documentation and the M1 sources exist; this is **not a compiled or tested UVC**. No tool is approved for this repository yet; every compile, elaboration and simulation stage is NOT RUN. Actual status and next steps are in `WORK_STATUS.md`.

**Git workflow:** the work is on the session-designated branch `claude/ecstatic-allen-kiy9we`, created from `dev` at `c8db5da` (D-010). New work starts on a feature branch from `dev` (GIT-01) once this branch is merged. Do not merge without the owner's request.
