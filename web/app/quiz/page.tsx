import type { Metadata } from "next";
import { QuizView } from "./QuizView";

export const metadata: Metadata = { title: "Quiz", robots: { index: false, follow: false } };

export default function Page() {
  return <QuizView />;
}
