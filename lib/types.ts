export type Profile = {
  id: string;
  full_name: string;
  email: string;
  role: "student" | "admin";
  subscription_status: "trial" | "active" | "expired" | "blocked";
  trial_ends_at: string;
  access_ends_at: string | null;
  created_at: string;
};

export type Question = {
  id: string;
  category: string;
  statement: string;
  options: string[];
  correct_answer: number;
  explanation: string;
  active: boolean;
};

export type Attempt = {
  id: string;
  category: string;
  total_questions: number;
  correct_answers: number;
  score_percent: number;
  created_at: string;
};

export type PaymentRequest = {
  id: string;
  amount: number;
  status: "pending" | "approved" | "rejected";
  proof_path: string | null;
  created_at: string;
  user_id: string;
  profiles?: { full_name: string; email: string } | null;
};
