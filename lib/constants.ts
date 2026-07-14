import {
  BookOpenCheck, ClipboardList, FireExtinguisher, HeartPulse, Map, Waves
} from "lucide-react";

export const CATEGORIES = {
  NR: {
    title: "Normas Regulamentadoras",
    short: "NR",
    description: "Segurança e saúde no trabalho.",
    icon: ClipboardList
  },
  NT: {
    title: "Normas Técnicas",
    short: "NT",
    description: "Conteúdo técnico e prevenção.",
    icon: BookOpenCheck
  },
  Extintores: {
    title: "Extintores",
    short: "EXT",
    description: "Classes, agentes e utilização.",
    icon: FireExtinguisher
  },
  Mapas: {
    title: "Mapas e plantas",
    short: "MAP",
    description: "Rotas, símbolos e abandono.",
    icon: Map
  },
  APH: {
    title: "APH",
    short: "APH",
    description: "Atendimento pré-hospitalar.",
    icon: HeartPulse
  },
  Mangueiras: {
    title: "Mangueiras",
    short: "MANG",
    description: "Linhas, conexões e operação.",
    icon: Waves
  }
} as const;

export type CategoryKey = keyof typeof CATEGORIES;

export const PLAN_PRICE = 15;
export const TRIAL_HOURS = 24;
