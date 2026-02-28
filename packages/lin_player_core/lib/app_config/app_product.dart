enum AppProduct { lin, uhd }

AppProduct appProductFromId(String? id) {
  switch ((id ?? '').trim().toLowerCase()) {
    case 'uhd':
      return AppProduct.uhd;
    case 'lin':
    default:
      return AppProduct.lin;
  }
}

extension AppProductX on AppProduct {
  String get id {
    switch (this) {
      case AppProduct.lin:
        return 'lin';
      case AppProduct.uhd:
        return 'uhd';
    }
  }

  String get displayName {
    switch (this) {
      case AppProduct.lin:
        return 'LinPlayer';
      case AppProduct.uhd:
        return 'UPlayer';
    }
  }
}

