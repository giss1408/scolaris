/// Every visible text, in French (the only market). One file keeps wording consistent and ready to move to ARB files if a second language comes.
abstract final class S {
  static const appName = 'Scolaris';
  static const retry = 'Réessayer';
  static const cancel = 'Annuler';
  static const confirm = 'Confirmer';
  static const save = 'Enregistrer';
  static const next = 'Suivant';
  static const back = 'Retour';
  static const finish = 'Terminer';
  static const search = 'Rechercher';
  static const required = 'Champ obligatoire';

  // Sign-in
  static const signIn = 'Se connecter';
  static const phone = 'Numéro de téléphone';
  static const phoneHelp = 'Ex. 07 01 02 03 04';
  static const password = 'Mot de passe';
  static const activateTitle = 'Activer mon compte';
  static const activateHelp = 'Entrez le code reçu par WhatsApp et choisissez votre mot de passe.';
  static const activationCode = 'Code reçu (6 chiffres)';
  static const newPassword = 'Nouveau mot de passe';
  static const haveCode = "J'ai reçu un code d'activation";
  static const backToSignIn = 'Retour à la connexion';
  static const activate = 'Activer';

  // Navigation
  static const tabHome = 'Accueil';
  static const tabStudents = 'Élèves';
  static const tabArrears = 'Impayés';
  static const tabProfile = 'Profil';

  // Home
  static String hello(String name) => 'Bonjour $name';
  static const collectedToday = "Encaissé aujourd'hui";
  static const collectedMonth = 'Encaissé ce mois';
  static const remaining = 'Reste à payer';
  static const overdue = 'En retard';
  static const recovery = 'Taux de recouvrement';
  static const pay = 'Encaisser';
  static const newStudent = 'Nouvel élève';
  static const toHandle = 'À traiter';
  static const seeAll = 'Voir tout';

  // Students
  static const noStudents = 'Aucun élève pour le moment.';
  static const noResult = 'Aucun résultat.';
  static const searchStudent = 'Nom, prénom ou matricule';
  static const studentSheet = "Fiche de l'élève";
  static const contacts = 'Contacts';
  static const family = 'Famille';
  static const account = 'Situation financière';
  static const history = 'Historique des paiements';
  static const call = 'Appeler';
  static const whatsapp = 'WhatsApp';
  static const assigned = 'Affecté';
  static const notAssigned = 'Non affecté';

  // Payments
  static const amount = 'Montant (FCFA)';
  static const method = 'Moyen de paiement';
  static const reference = "Référence de l'opérateur";
  static const referenceHelp = 'Numéro de transaction ou de chèque';
  static const paymentDone = 'Paiement enregistré';
  static const share = 'Partager';
  static const cancelPayment = 'Annuler ce paiement';
  static const cancelReason = "Motif de l'annulation";
  static const cancelledBadge = 'Annulé';
  static const grantDiscount = 'Accorder une réduction';
  static const discountReason = 'Motif';
  static const paid = 'Payé';
  static const late = 'En retard';
  static const toPay = 'À payer';
  static const total = 'Total dû';
  static const received = 'Déjà réglé';
  static const rePassword = 'Pour votre sécurité, confirmez votre mot de passe.';

  // Arrears
  static const noArrears = 'Aucun impayé. Bravo !';
  static String lateDays(int d) => d <= 1 ? 'Retard de $d jour' : 'Retard de $d jours';
  static String children(int n) => n <= 1 ? '1 enfant' : '$n enfants';

  // Student form
  static const stepIdentity = 'Identité';
  static const stepParent = 'Parent';
  static const stepClass = 'Classe';
  static String step(int i, int n) => 'Étape $i sur $n';
  static const lastName = 'Nom';
  static const firstNames = 'Prénoms';
  static const sex = 'Sexe';
  static const male = 'Garçon';
  static const female = 'Fille';
  static const birthDate = 'Date de naissance';
  static const birthPlace = 'Lieu de naissance';
  static const matricule = 'Matricule national (MENA)';
  static const matriculeHelp = 'Facultatif, unique pour chaque élève';
  static const assignedByState = "Élève affecté par l'État";
  static const parentName = 'Nom du parent ou tuteur';
  static const relation = 'Lien';
  static const optin = "Le parent accepte de recevoir les messages de l'école sur WhatsApp";
  static const financialResp = 'Responsable des paiements';
  static const classroom = 'Classe';
  static const options = 'Services choisis';
  static const summary = 'Récapitulatif';
  static const createStudent = "Inscrire l'élève";

  // Profile
  static const account_ = 'Compte';
  static const school = 'Établissement';
  static const application = 'Application';
  static const changePassword = 'Changer mon mot de passe';
  static const team = 'Équipe';
  static const fees = 'Frais de scolarité';
  static const classes = 'Classes';
  static const signOut = 'Se déconnecter';
  static const signOutAsk = 'Se déconnecter de Scolaris ?';
  static const currentPassword = 'Mot de passe actuel';
  static const passwordChanged = 'Mot de passe modifié';
  static const addMember = 'Ajouter un membre';
  static const memberName = 'Nom complet';
  static const memberRole = 'Fonction';
  static const memberHelp = "Le compte sera activé avec un code envoyé par WhatsApp par l'équipe Scolaris.";
  static const memberAdded = 'Membre ajouté. Un code WhatsApp lui sera envoyé.';
  static const remove = 'Retirer';
  static const forbidden = "Cette action n'est pas disponible pour votre fonction.";
  static const addLine = 'Ajouter une ligne';
  static const label = 'Libellé';
  static const dueDate = 'Date limite';
  static const optional = 'Facultatif';
  static const className = 'Nom de la classe';
  static const level = 'Niveau';
  static const addClass = 'Ajouter une classe';

  static String role(String r) => switch (r) {
        'director' => 'Directeur / Directrice',
        'accountant' => 'Comptable / Caissier',
        'secretary' => 'Secrétaire',
        _ => r,
      };
  static String methodLabel(String m) => switch (m) {
        'especes' => 'Espèces',
        'wave' => 'Wave',
        'orange_money' => 'Orange Money',
        'mtn_momo' => 'MTN MoMo',
        'moov_money' => 'Moov Money',
        'virement' => 'Virement',
        'cheque' => 'Chèque',
        _ => m,
      };
  static String kindLabel(String k) => switch (k) {
        'inscription' => 'Inscription',
        'scolarite' => 'Scolarité',
        'cantine' => 'Cantine',
        'transport' => 'Transport',
        'tenue' => 'Tenue',
        'fournitures' => 'Fournitures',
        'assurance' => 'Assurance',
        'coges' => 'COGES',
        'examen' => 'Frais d\'examen',
        'parascolaire' => 'Parascolaire',
        _ => k,
      };
  static String relationLabel(String r) => switch (r) { 'pere' => 'Père', 'mere' => 'Mère', 'tuteur' => 'Tuteur', _ => 'Autre' };
}
